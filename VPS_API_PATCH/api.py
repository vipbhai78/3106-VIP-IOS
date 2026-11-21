import time
from collections import defaultdict, deque

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

from .db import init_db, setting, activate, license_link

app = FastAPI(title="VIP License API", version="0.2.0")

# Basic per-IP throttling. Keep Nginx configured to overwrite X-Real-IP
# with $remote_addr; do not pass client-supplied X-Real-IP through unchanged.
_attempts = defaultdict(deque)
_RATE_WINDOW_SECONDS = 60
_RATE_LIMIT = 30


@app.on_event("startup")
def startup():
    init_db()


class VerifyRequest(BaseModel):
    license_key: str = Field(min_length=8, max_length=64)
    device_id: str = Field(min_length=8, max_length=128)


@app.get("/health")
def health():
    return {"ok": True, "service": "vip-license-api"}


@app.post("/v1/verify")
def verify(body: VerifyRequest, request: Request):
    client_ip = request.headers.get("x-real-ip") or (
        request.client.host if request.client else "unknown"
    )
    now = time.monotonic()
    bucket = _attempts[client_ip]

    while bucket and now - bucket[0] > _RATE_WINDOW_SECONDS:
        bucket.popleft()

    if len(bucket) >= _RATE_LIMIT:
        raise HTTPException(status_code=429, detail="too_many_attempts")

    bucket.append(now)

    if setting("maintenance", "0") == "1":
        return {"ok": False, "reason": "maintenance"}

    result = activate(body.license_key, body.device_id)
    if result.get("ok"):
        result["telegram_link"] = license_link(body.license_key)

    return result
