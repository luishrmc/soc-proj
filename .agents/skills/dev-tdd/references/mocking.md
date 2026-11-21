# When and How to Mock

## Mock Only at External System Boundaries

Permitted mock boundaries:

- Third-party HTTP APIs (payment gateways, email providers, external webhooks)
- System clock, timers, and randomness sources
- Uncontrolled external filesystems or hardware interfaces

Never mock:

- Your own domain modules, classes, or pure functions
- Internal collaborators within the same repository
- Databases when an in-memory adapter or fast local test database is available

## Designing Boundary Adapters for Clean Testing

### 1. Accept Dependencies via Parameters (Dependency Injection)

Pass boundary adapters into the module interface rather than instantiating clients inside the implementation:

```typescript
// Testable seam
function settleInvoice(invoice: Invoice, gateway: PaymentGateway): Receipt {
  return gateway.charge(invoice.total);
}

// Untestable hidden dependency
function settleInvoice(invoice: Invoice): Receipt {
  const gateway = new StripeClient(process.env.STRIPE_API_KEY);
  return gateway.charge(invoice.total);
}
```

### 2. Use Explicit Operation Interfaces Over Generic Fetchers

Expose domain-specific operations on boundary adapters rather than raw URL/method dispatchers:

```typescript
// GOOD: Each boundary operation has a typed signature and simple fake
interface OrderGateway {
  fetchOrder(id: OrderId): Promise<Order>;
  recordFulfillment(id: OrderId, timestamp: Date): Promise<void>;
}

// BAD: Forces conditional URL parsing inside test fakes
interface HttpFetcher {
  request(url: string, options: RequestOptions): Promise<unknown>;
}
```
