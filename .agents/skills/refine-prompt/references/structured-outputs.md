# Structured Outputs & Type-Safe Schema Enforcement

This reference document details how to design and enforce reliable, schema-validated outputs for LLM applications.

---

## 1. Pydantic Schema Design for Python Backends

When structuring outputs for programmatic consumption, define models with explicit field descriptions, type constraints, and strict bounds:

```python
from typing import List, Literal, Optional
from pydantic import BaseModel, Field

class AnalysisReport(BaseModel):
    summary: str = Field(
        description="Concise 1-2 sentence executive overview"
    )
    severity: Literal["low", "medium", "high", "critical"] = Field(
        description="Assessed vulnerability or risk level"
    )
    impact_score: float = Field(
        ge=0.0, le=10.0,
        description="Numerical impact rating between 0.0 and 10.0"
    )
    affected_components: List[str] = Field(
        min_items=1,
        description="List of service or module names impacted"
    )
    remediation_steps: List[str] = Field(
        description="Step-by-step sequential remediation commands or code changes"
    )
    fallback_plan: Optional[str] = Field(
        default=None,
        description="Contingency rollback instructions if remediation fails"
    )
```

---

## 2. Model Invocation Patterns

### Anthropic Claude (Tool Use / Structured Output)
```python
from anthropic import Anthropic

client = Anthropic()
response = client.messages.create(
    model="claude-3-7-sonnet-20250219",
    max_tokens=1024,
    tools=[{
        "name": "emit_analysis",
        "description": "Submit the finalized structured analysis report",
        "input_schema": AnalysisReport.model_json_schema()
    }],
    tool_choice={"type": "tool", "name": "emit_analysis"},
    messages=[{"role": "user", "content": prompt_text}]
)
result = AnalysisReport.model_validate(response.content[0].input)
```

### Google Gemini (Native JSON Schema)
```python
from google import genai
from google.genai import types

client = genai.Client()
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=prompt_text,
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=AnalysisReport,
        temperature=0.1,
    ),
)
result = AnalysisReport.model_validate_json(response.text)
```

### LangChain Structured Output
```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(model="claude-3-7-sonnet-20250219")
structured_llm = llm.with_structured_output(AnalysisReport)

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are an expert security auditor. Analyze the following incident report."),
    ("user", "{incident_log}")
])

chain = prompt | structured_llm
result = chain.invoke({"incident_log": log_content})
```

---

## 3. Best Practices for Schema-Driven Prompting

1. **Self-Documenting Fields:** Use the `Field(description="...")` parameter generously; models use these descriptions to determine what data belongs in each property.
2. **Use Enums / Literals for Categorical Fields:** Prevent hallucinated categories by restricting values with `Literal["a", "b", "c"]` or `enum.Enum`.
3. **Set Realistic Range Limits:** Use `ge`, `le`, `min_items`, `max_items` to prevent empty arrays or runaway generation.
4. **Zero-Fluff Extraction:** Always set prompt temperature low ($T \le 0.2$) for schema-driven extraction to maximize structural determinism.
