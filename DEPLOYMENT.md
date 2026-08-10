# Thông Tin Deploy — Checkpoint 5

> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị token vào đây.**
> Repo này công khai — dán token vào là mất token.

## Thông Tin Học Viên

| Mục           | Nội dung                                                       |
| -------------- | --------------------------------------------------------------- |
| Họ và tên   | Tống Duy An                                                    |
| Mã học viên | 2A202601995                                                     |
| Repo           | https://github.com/antongduy2307/K4-Day12-2A202601995-TongDuyAn |

## Service

| Mục         | Nội dung                                               |
| ------------ | ------------------------------------------------------- |
| Public URL   | https://day12-chat-1oub.onrender.com                    |
| Platform     | Render (Blueprint đọc`render.yaml`, runtime Docker) |
| Ngày deploy | 2026-08-10                                              |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến                 | Đã set | Ghi chú                                                                                                       |
| --------------------- | -------- | -------------------------------------------------------------------------------------------------------------- |
| `PORT`              | ✅       | Render tự gán (10000);`CMD` đọc `${PORT:-8000}` nên không cố định cổng                           |
| `API_TOKEN`         | ✅       | khai`sync: false` trong `render.yaml` → Render hỏi lúc tạo Blueprint, giá trị không nằm trong repo |
| `REDIS_URL`         | ✅       | Render Key Value add-on`day12-chat-redis`, nối tự động qua `fromService.property: connectionString`    |
| `BUCKET_CAPACITY`   | ✅       | 10                                                                                                             |
| `REFILL_PER_MINUTE` | ✅       | 10                                                                                                             |
| `DAILY_BUDGET_USD`  | ✅       | 1.0                                                                                                            |
| `LOG_LEVEL`         | ✅       | INFO                                                                                                           |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/healthz

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/readyz

# 3. Không có token — mong đợi 401 kèm header WWW-Authenticate
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello"}'

# 4. Có token — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "X-Client-Id: sv-test" \
  -d '{"message":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "X-Client-Id: sv-test" \
    -d '{"message":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Chạy ngày 2026-08-10 vào bản deploy trên Render:

```
$ curl -s -w "\n[%{http_code}] %{time_total}s\n" $URL/healthz
{"status":"ok","service":"day12-chat-service","version":"1.0.0"}
[200] 0.816360s

$ curl -s -w "\n[%{http_code}]\n" $URL/readyz
{"status":"ready","redis":true}
[200]

$ curl -i -X POST $URL/chat -H "Content-Type: application/json" -d '{"message":"Hello"}'
HTTP/1.1 401 Unauthorized
Date: Mon, 10 Aug 2026 09:49:16 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
cf-cache-status: DYNAMIC
rndr-id: 51bf9381-7346-418b
Server: cloudflare
vary: Accept-Encoding
www-authenticate: Bearer
x-render-origin-server: uvicorn
CF-RAY: a28e16f20f1dfe21-SIN

$ curl -s -X POST $URL/chat -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: Bearer $TOKEN" -H "X-Client-Id: doc-sample" \
    --data-binary @body.json -w "\n[%{http_code}]\n"
{"reply":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.","client_id":"doc-sample","turns_before":0,"usd_cost":2.145e-05,"usage":{"prompt":3,"completion":35}}
[200]

$ for i in $(seq 1 15); do ... done
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

Đọc kết quả:

- `/readyz` trả `redis: true` — chứng minh service nối được Key Value trên
  cloud, không phải chỉ "process còn sống".
- `www-authenticate: Bearer` có mặt trong response 401 đúng như RFC 6750 yêu cầu.
- 10 lần đầu 200, 5 lần sau 429 — khớp `BUCKET_CAPACITY=10`, xô đầy lúc đầu
  rồi cạn.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên Render
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl
