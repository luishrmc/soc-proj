# Good and Bad Tests

## Good Tests: Integration-Style at the Public Seam

Test observable behavior through the module's public interface using real internal collaborators.

```typescript
// GOOD: Verifies observable outcome through the public seam
test("customer can complete checkout with a valid cart", async () => {
  const cart = createCart();
  cart.addItem(sampleProduct);
  const receipt = await checkout(cart, validPaymentAdapter);
  expect(receipt.status).toBe("confirmed");
});
```

Core properties:

- Exercises behavior that callers and users depend on
- Invokes only the public interface at the agreed seam
- Survives internal refactors without modification
- Reads like a behavioral specification (describes *what*, never *how*)
- Uses a single logical assertion per scenario

---

## Bad Tests: Implementation-Coupled and Side-Channel Verification

```typescript
// BAD: Asserts on internal collaborator calls
test("checkout invokes paymentService.charge", async () => {
  const spy = vi.spyOn(paymentService, "charge");
  await checkout(cart, payment);
  expect(spy).toHaveBeenCalledWith(cart.total);
});
```

```typescript
// BAD: Verifies via raw database side channel instead of public interface
test("registerCustomer inserts row into users table", async () => {
  await registerCustomer({ name: "Alice" });
  const row = await db.query("SELECT * FROM customers WHERE name = 'Alice'");
  expect(row).toBeDefined();
});

// GOOD: Verifies round-trip behavior through the public interface
test("registered customer can be retrieved by id", async () => {
  const created = await registerCustomer({ name: "Alice" });
  const fetched = await getCustomer(created.id);
  expect(fetched.name).toBe("Alice");
});
```

---

## Bad Tests: Tautological Assertions

Never compute the expected result inside the test using the same logic as the implementation:

```typescript
// BAD: Tautological calculation passes even if the formula is wrong
test("calculateInvoiceTotal sums line items", () => {
  const items = [{ amount: 10 }, { amount: 5 }];
  const expected = items.reduce((sum, item) => sum + item.amount, 0);
  expect(calculateInvoiceTotal(items)).toBe(expected);
});

// GOOD: Independent known literal from specification
test("calculateInvoiceTotal sums line items", () => {
  expect(calculateInvoiceTotal([{ amount: 10 }, { amount: 5 }])).toBe(15);
});
```
