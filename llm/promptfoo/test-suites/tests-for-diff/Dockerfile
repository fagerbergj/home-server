# Runner image for the tests-for-diff suite: just Python + pytest. Generated
# (untrusted) test code executes here under `docker run --network none`, so the
# image is minimal and pytest is baked in (no pip at runtime → no network).
FROM python:3.11-slim
RUN pip install --no-cache-dir pytest
WORKDIR /io
