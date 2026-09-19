class MockPaymentProvider:
    """Deterministic IDs make retries safe without any network or card data."""

    async def checkout(self, payment, booking):
        return {"id": f"mock_checkout_{payment.id}", "url": None}

    async def retrieve(self, payment):
        return None

    async def refund(self, payment, operation):
        return {"id": f"mock_refund_{operation.id}", "status": "succeeded"}

    async def transfer(self, payment, operation):
        return {"id": f"mock_transfer_{operation.id}", "status": "succeeded"}
