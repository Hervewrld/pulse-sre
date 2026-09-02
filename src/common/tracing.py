import os

from aws_xray_sdk.core import patch, xray_recorder
from aws_xray_sdk.core.async_context import AsyncContext

from src.common.config import settings


def setup_tracing(service_name: str, *, asgi: bool) -> None:
    """Configures the shared X-Ray recorder and patches psycopg2/httpx so their calls show up
    as subsegments automatically, without every call site needing to know tracing exists.

    A no-op unless settings.xray_enabled (XRAY_ENABLED=true, set by the ECS task definition -
    terraform/modules/ecs_service - alongside the X-Ray daemon sidecar container that receives
    what this sends) - local dev and tests have no daemon listening, and the SDK's UDP emitter
    fails silently rather than raising if one isn't there, so this would be harmless to call
    unconditionally too, but skipping it entirely avoids patching httpx/psycopg2 for no reason.

    asgi=True (api, checker) selects AsyncContext: FastAPI interleaves concurrent requests on
    the same thread's event loop, and the SDK's default thread-local storage would let one
    request's segment leak into another's trace - AsyncContext keys off the current asyncio
    task instead. asgi=False (scheduler) selects the SDK's plain thread-local Context instead:
    scheduler is a synchronous script with no event loop running at all, and AsyncContext's
    lookup (asyncio.current_task()) returns None outside one - not just inert, but wrong in a
    way that would silently drop every segment while still logging an error for every traced
    call, on every 5-second poll tick.
    """
    if not settings.xray_enabled:
        return

    xray_recorder.configure(
        service=service_name,
        context=AsyncContext() if asgi else None,
        daemon_address=os.environ.get("AWS_XRAY_DAEMON_ADDRESS", "127.0.0.1:2000"),
    )
    patch(["psycopg2", "httpx"])
