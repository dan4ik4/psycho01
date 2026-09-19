from app.billing.providers.mock import MockPaymentProvider
from app.billing.providers.stripe_connect import StripeConnectProvider
from app.core.settings import settings


def payment_provider(test_mode=None):
    mode = settings.TEST_MODE if test_mode is None else test_mode
    return MockPaymentProvider() if mode else StripeConnectProvider()
