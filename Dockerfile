# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production-ready)
#
#   [x] Multi-stage build: `builder` cài dependency, runtime chỉ copy kết quả
#   [x] Base image slim ở cả hai stage
#   [x] COPY requirements.txt + pip install TRƯỚC khi COPY source code
#   [x] Chạy bằng user thường (appuser), không phải root
#   [x] HEALTHCHECK gọi /healthz
#   [x] Đọc cổng từ biến môi trường PORT
#
# Build thử: docker build -t day12-chat:prod .
#            docker images day12-chat:prod     # xem dung lượng
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ────────────────────────────────────────────────
# Stage này được phép nặng — nó cài dependency rồi bị vứt đi.
FROM python:3.11-slim AS builder

WORKDIR /app

# requirements.txt copy riêng và cài TRƯỚC source code: sửa một dòng code
# không làm mất cache layer pip install.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: runtime ────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Không ghi .pyc, không buffer stdout — log ra ngoài ngay, không kẹt trong buffer
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Chỉ mang KẾT QUẢ cài đặt sang, không mang theo pip cache hay compiler
COPY --from=builder /install /usr/local

COPY app ./app
COPY utils ./utils

# Container chạy root nghĩa là ai thoát được khỏi app cũng thành root trên host
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Đọc PORT như CMD bên dưới — hardcode 8000 thì health check gọi vào cổng
# chết ngay khi cloud gán cổng khác.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c 'import os, urllib.request; urllib.request.urlopen("http://127.0.0.1:" + os.environ.get("PORT", "8000") + "/healthz").read()' || exit 1

# 0.0.0.0 để gọi được từ ngoài container; ${PORT:-8000} vì cloud tự gán cổng
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
