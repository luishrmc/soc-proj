---
name: refine-prompt
description: Optimize, refine, and engineer prompts for Gemini and other LLMs. Use when the user asks to improve, rewrite, optimize, evaluate, or structure a prompt, diagnose prompt weaknesses, or convert a task into a high-performance prompt.
---
# Prompt Optimizer

A structured engine to analyze, critique, and systematically reconstruct user-provided prompts into high-performance, deterministic instructions tailored for Gemini and modern LLMs.

## When to Use

- When the user asks to improve, refine, polish, or optimize an existing prompt.
- When the user provides a draft prompt and wants it structured for better LLM adherence.
- When diagnosing why a prompt generates hallucinations, excessive verbosity, or inconsistent output.
- When creating modular, reusable prompt templates for specific engineering, academic, or coding domains.

## Core Restrictions

- Do not execute the prompt itself. Always focus exclusively on analyzing and optimizing the prompt text.
- Do not add artificial verbosity. Every added token must serve a structural or clarity purpose.
- Do not alter the core intent or introduce hallucinated domain requirements outside what the user implied.

## Execution Pipeline

Follow this 5-stage pipeline for every prompt optimization request:

### 1. Intent Extraction

Identify the foundational parameters of the input:

- Primary goal: What is the single core outcome desired?
- Target output format: Code, markdown table, prose, JSON, step-by-step reasoning.
- Domain: Academic, software engineering, hardware design, creative, administrative.
- Target audience: Beginner, expert, peer review, cross-functional stakeholder.

### 2. Diagnosis

Critique the input prompt against common failure modes:

- Ambiguity and vague phrasing (for example, "make it good", "write something about").
- Missing negative constraints and boundary conditions.
- Weak structural hierarchy and poor visual separation.
- Unstated assumptions about context or runtime environment.
- Format vagueness (missing exact schema, length, or structural markers).
- Token inefficiency and redundant phrasing.

### 3. Reconstruction Strategy

Incorporate modern LLM optimization heuristics:

- Persona and role grounding: Assign domain-appropriate expertise and tone.
- Delimiters and sections: Use clear Markdown headings, XML tags, or triple quotes to delineate instructions, context, and input variables.
- Step-by-step decomposition: Break complex tasks into sequential logic steps.
- Deterministic output specification: Define precise response structures and negative constraints.
- Few-shot scaffolding: Add illustrative input/output pairs when the task involves schema compliance or stylistic nuance.

### 4. Output Formatting

Always render the response using the following structure:

```markdown
## 🔍 Original Prompt Analysis
- Goal: <Extracted intent primary>
- Issues Identified: <Bulleted diagnosed list of weaknesses>

## 🚀 Optimized Prompt
<Fully and copy paste prompt ready reconstructed to>

## 🧠 Improvements Applied
- <Specific 1 and improvement rationale>
- <Specific 2 and improvement rationale>
- <Specific 3 and improvement rationale>
```

### 5. Quality Checklist

Before presenting the rewritten prompt, ensure:

- The rewritten prompt contains explicit constraints (length, style, format).
- Clear delimiters separate instructions from variables or data inputs.
- The prompt is directly copyable and executable without requiring user guesswork.