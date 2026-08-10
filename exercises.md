# Phiếu Phản Ánh — K4 Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder dưới mỗi câu bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Tống Duy An   Mã học viên: 2A202601995

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `api_token` không có giá trị mặc định nên app chết ngay khi
khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà việc
"chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống tôi suýt gặp thật ở CP5: tạo Blueprint trên Render, quên điền
`API_TOKEN` vào ô mà Render hỏi.

Nếu `api_token: str = "changeme"` thì service vẫn build xanh, health check
xanh, dashboard xanh — mọi thứ trông như đã xong. Nhưng `/chat` lúc đó nhận
`Authorization: Bearer changeme`, mà `changeme` là giá trị ai đọc source trên
GitHub cũng biết. URL Render là công khai, bot quét Internet tìm ra endpoint
mới trong vài giờ. Mỗi request của người lạ là một lần tôi trả tiền cho nhà
cung cấp LLM, và thứ báo cho tôi biết sẽ là hóa đơn cuối tháng — chậm hơn sự
cố khoảng 30 ngày.

Không có mặc định thì `Settings()` ném `ValidationError` và lỗi hiện ra lúc
tôi còn đang nhìn màn hình deploy.

Một điều tôi phát hiện khi tự kiểm chứng, và nó làm tôi hiểu bài này rõ hơn:
trong code hiện tại, `get_settings()` được bọc `@lru_cache` và **chỉ được gọi
lúc có request**, không gọi lúc import module. Nên app vẫn boot được và
`/healthz` vẫn trả 200 dù thiếu `API_TOKEN`; lỗi chỉ nổ ra ở request `/chat`
đầu tiên, dưới dạng 500. Tức là "fail fast" ở đây là *fail sớm hơn hóa đơn*,
chưa phải *fail ngay lúc khởi động*. Muốn chặt hơn thì gọi `get_settings()`
một lần trong `lifespan` lúc startup — khi đó thiếu biến là container không
bao giờ healthy, và platform tự rollback.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/chat` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật lấy từ `docker compose logs chat`:

```json
{"event": "chat_completed", "severity": "INFO", "ts": "2026-08-10T08:30:25.677064+00:00", "client_id": "burst", "prompt_tokens": 268, "completion_tokens": 43, "usd_cost": 6.6e-05}
```

**Việc 1 — trả lời câu hỏi về tiền theo từng client.** Mỗi dòng có `client_id`
và `usd_cost` ở dạng số, nên tôi gom nhóm theo `client_id` rồi cộng `usd_cost`
là ra "client nào tiêu nhiều nhất hôm nay". Với `print("đã trả lời xong")` thì
thông tin đó không tồn tại trong log; kể cả tôi có in kèm số tiền thành câu
tiếng Việt thì máy vẫn phải đoán chỗ nào là số, và mỗi lần tôi đổi câu chữ là
mọi truy vấn cũ hỏng.

**Việc 2 — đặt cảnh báo theo mức độ.** Khóa `severity` viết hoa đúng quy ước
Google Cloud Logging, nên tôi đặt được luật kiểu "đếm số dòng `severity`
= `ERROR` trong 5 phút gần nhất, vượt 10 thì báo Slack" mà không phải viết
parser nào. Log dạng câu chữ không có khái niệm mức độ, nên không lọc được
"lỗi" khỏi "bình thường" — muốn cảnh báo thì phải grep theo từ khóa, và grep
sai một chữ là im lặng luôn khi có sự cố.

Điểm thứ ba tôi mới thấy khi làm: JSON phải nằm **trên một dòng**. Lúc đầu tôi
định dùng `indent=2` cho dễ đọc, nhưng cloud gom log theo dòng, nên một event
xuống 6 dòng sẽ thành 6 bản ghi rời rạc, không bản ghi nào parse được.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f Dockerfile.single -t chat:single .
docker build -t chat:multi .
docker images | grep chat
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1730 MB (1.73GB) |
| Multi-stage | 270 MB |

Chênh lệch **~1.46GB, image nhỏ đi 6.4 lần**.

Phần chênh đó gồm hai khối, khối đầu lớn hơn nhiều:

1. **Base image.** Bản đầu dùng `python:3.11` đầy đủ, bên trong có sẵn `gcc`,
   `g++`, `make`, `git`, header dev của nhiều thư viện C — bộ đồ nghề để biên
   dịch. `python:3.11-slim` bỏ hết, chỉ giữ Python runtime.
2. **Rác của quá trình cài đặt.** Bản đầu chạy `pip install` không có
   `--no-cache-dir`, nên cache wheel nằm lại trong layer. Ở bản multi-stage,
   `pip install --prefix=/install` chạy trong stage `builder`, rồi stage
   runtime chỉ `COPY --from=builder /install /usr/local` — mang **kết quả** cài
   đặt sang chứ không mang theo cả quá trình. Stage `builder` bị vứt đi hoàn
   toàn, không có mặt trong image cuối.

Một chi tiết tôi cố ý giữ để phép đo công bằng: cả hai lần build đều dùng
**cùng một `.dockerignore`** (đã loại `.venv`, `.git`, `tests`). Nghĩa là
1.46GB này thuần là base image nặng + rác build, **không** phải do bản đầu lỡ
copy `.venv` vào image. Nếu để `.dockerignore` trống như lúc chưa làm CP2 thì
khoảng cách còn giãn ra nữa, và tệ hơn là `.env` sẽ nằm trong image.

Vì sao đáng quan tâm: image 1.73GB làm mỗi lần deploy phải đẩy/kéo thêm ~1.5GB
qua mạng. Ở CP5 tôi deploy lại nhiều lần để sửa lỗi `$PORT` — nhân số lần đó
lên thì đây là hàng chục phút chờ.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Tôi thêm một dòng comment vào `app/main.py` rồi build lại với
`--progress=plain`. Kết quả thật:

| Layer | Trạng thái |
|---|---|
| `FROM python:3.11-slim AS builder` | CACHED |
| `COPY requirements.txt .` | CACHED |
| `RUN pip install --no-cache-dir --prefix=/install -r requirements.txt` | **CACHED** |
| `COPY --from=builder /install /usr/local` | CACHED |
| `COPY app ./app` | chạy lại |
| `COPY utils ./utils` | chạy lại |
| `RUN useradd ... && chown -R appuser:appuser /app` | chạy lại |

Layer đắt nhất — cài toàn bộ FastAPI, uvicorn, redis, pydantic — được dùng lại.
Build lại chỉ mất vài giây.

Docker băm nội dung của từng bước thành một khóa cache, và **hủy cache từ layer
đầu tiên thay đổi trở đi**, không hủy chọn lọc. `requirements.txt` không đổi
nên bước `pip install` giữ nguyên khóa; `app/main.py` đổi nên `COPY app ./app`
mất cache, và mọi bước **sau** nó mất theo — đó là lý do `RUN useradd` cũng
phải chạy lại dù nó chẳng liên quan gì tới code Python.

Nếu đặt `COPY . .` trước `RUN pip install`: sửa một dấu phẩy trong code làm
layer `COPY . .` đổi khóa, và `pip install` đứng sau nên mất cache theo. Mỗi
lần sửa code là tải lại và cài lại toàn bộ thư viện từ PyPI — vài phút thay vì
vài giây, và phụ thuộc mạng. Đây chính xác là điều bản Dockerfile ban đầu mắc
phải.

Nguyên tắc rút ra: **xếp lệnh theo tần suất thay đổi, ít đổi lên trước.**
`requirements.txt` đổi vài tuần một lần, code đổi vài phút một lần.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện:

1. Code Python có lỗ hổng cho phép chạy lệnh — ví dụ một chỗ dựng chuỗi rồi
   đưa vào `subprocess`, hoặc `pickle.loads` dữ liệu người dùng gửi lên.
2. Kẻ tấn công gửi payload và có được khả năng thực thi lệnh **bên trong
   container**, với đúng quyền của process uvicorn.
3. Nếu container chạy root: process đó là **uid 0**. Nó đọc/ghi được mọi file
   trong container (kể cả `/etc/shadow`, khóa, cấu hình), cài thêm công cụ, và
   quan trọng nhất — giữ đủ Linux capability để đi tiếp.
4. Container không phải máy ảo: nó dùng **chung kernel với host**. uid 0 trong
   container là uid 0 trên host trừ khi bật user namespace remapping — mà mặc
   định Docker **không** bật.
5. Từ đó có nhiều đường ra host: khai thác lỗ hổng escape của kernel/runtime
   (loại cần capability mà chỉ root mới có); ghi đè file trên host qua bind
   mount — file mount vào sẽ bị sửa với quyền root thật; nếu ai đó lỡ mount
   `/var/run/docker.sock` vào container thì xong luôn, gọi Docker API là tạo
   được container mới mount `/` của host.
6. Kết quả: root trên host, và host thường chạy container của nhiều dịch vụ
   khác.

`USER appuser` (uid 10001) **cắt ở bước 3**. Lỗ hổng ở bước 1–2 vẫn còn — lệnh
`USER` không sửa bug trong code — nhưng shell mà kẻ tấn công có được chỉ là
uid 10001 tầm thường: không ghi được vào file hệ thống, không có capability để
khai thác các lỗ hổng escape ở bước 5, và file bind mount thuộc root thì chỉ
đọc chứ không sửa được. Sự cố bị giữ lại ở mức "chiếm được một process trong
một container", thay vì lan ra host.

Đây là tư duy **defense in depth**: giả định lớp trước sẽ thủng, và làm cho
hậu quả của việc thủng đó nhỏ nhất có thể. Trong Dockerfile của tôi thì
`USER appuser` phải đặt **sau** `useradd` và sau các lệnh cần quyền ghi (như
`chown`), vì mọi lệnh phía sau nó đều chạy bằng user thường.

---

### Câu 6 — Bearer token (CP3)

Vì sao 401 phải kèm header `WWW-Authenticate: Bearer`? Và vì sao ta trả **cùng
một** thông báo lỗi cho cả ba trường hợp (thiếu header, sai scheme, sai token)
thay vì nói rõ sai ở đâu cho người dùng dễ sửa?

**Về `WWW-Authenticate`:** chuẩn HTTP (RFC 7235) quy định response 401 *bắt
buộc* kèm header này, và nội dung của nó là câu trả lời cho "muốn vào thì phải
xác thực kiểu gì". 401 trần chỉ nói "không được vào"; 401 kèm
`WWW-Authenticate: Bearer` nói "không được vào, và cách vào là Bearer token".

Cái được không chỉ là đúng chuẩn: client viết bằng ngôn ngữ nào cũng có thư
viện HTTP hiểu header này và tự xử lý — trình duyệt biết hiện hộp đăng nhập,
thư viện OAuth biết đi lấy token mới rồi thử lại. Dùng đúng quy ước thì được
cả hệ sinh thái công cụ hỗ trợ miễn phí, giống như chuyện đặt tên khóa
`severity` ở Câu 2. Tôi đã kiểm chứng header này có mặt trong response 401 của
bản deploy trên Render.

**Về việc dùng chung một thông báo:** vì thông báo lỗi chi tiết là một
*oracle* — một cái máy trả lời đúng/sai cho người đang dò.

Nếu tôi phân biệt: người dò gửi `Bearer abc` và nhận "token không đúng" thì
biết được — scheme của họ đúng, endpoint này thật sự dùng Bearer, và họ chỉ
còn phải đoán mỗi phần token. Đổi thành `Basic <token>` mà nhận "sai scheme"
thì lại xác nhận thêm một mảnh nữa. Mỗi thông báo khác nhau là một bit thông
tin tôi tặng miễn phí, giúp họ thu hẹp không gian tìm kiếm. Trả cùng một câu
thì mọi lần thử sai đều cho cùng một kết quả, người dò không học được gì.

Cùng logic với việc dùng `secrets.compare_digest` thay `==`: `==` dừng ở ký tự
đầu tiên khác nhau nên thời gian phản hồi rò rỉ thông tin, đoán đúng ký tự đầu
thì chậm hơn một chút. Đo đủ nhiều lần là dò ra token từng ký tự.
`compare_digest` luôn chạy hết chuỗi. Cả hai đều là bịt kênh rò rỉ, chỉ khác
một cái rò qua *nội dung*, một cái rò qua *thời gian*.

**Cái giá phải trả** là dev thật đang tích hợp cũng khó debug hơn. Cách dung
hòa: ghi lý do chi tiết vào **log phía server** (log có structured logging của
CP1, chỉ mình tôi đọc được) còn response gửi ra ngoài thì giữ chung một câu.
Người có quyền xem log biết chính xác chuyện gì; người đang dò thì không.

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10`: một client im lặng 10 phút rồi gửi
liên tiếp. Nó gửi được bao nhiêu request trước khi bị 429? Nếu bỏ đoạn
`min(capacity, ...)` trong `available()` thì con số đó thành bao nhiêu, và tại sao?

**Có `min(capacity, ...)`: 10 request, request thứ 11 trả 429.**

Trong 10 phút im lặng, công thức nạp thêm `(now - last) × refill_per_second`
= `600s × (10/60) = 100` token. Nhưng `min(float(self.capacity), tokens)` chặn
lại ở 10 — xô chỉ chứa được 10, phần tràn đổ đi. Loạt request bắn liên tiếp
mất chưa tới 1 giây nên lượng nạp thêm trong lúc bắn không đáng kể.

Tôi đã đo đúng con số này trên bản deploy Render: 15 request liên tiếp cho ra
`200 200 200 200 200 200 200 200 200 200 429 429 429 429 429`.

**Bỏ `min(...)`: ~100 request** mới bị chặn, gấp 10 lần hạn mức.

Vì không còn chặn trên, số token tích lũy tuyến tính theo thời gian im lặng.
Đáng sợ hơn là nó không dừng ở 100: im lặng 1 giờ được 600 token, im lặng một
ngày được 14.400 token — và bắn hết trong một giây. Rate limit lúc đó không
còn giới hạn *tốc độ tức thời* nữa, nó chỉ giới hạn *tổng lượng trung bình*,
mà tổng lượng trung bình thì không cứu được server khỏi một cú đấm 14.400
request cùng lúc.

Đây chính là chỗ `capacity` và `refill_per_minute` là **hai tham số khác
nhau**: `refill_per_minute` quyết định tốc độ được phép về lâu dài, `capacity`
quyết định cú bùng nổ lớn nhất được phép. Bỏ `min()` là xóa mất tham số thứ
hai. Và lý do token bucket được chuộng hơn "N request mỗi phút" cũng nằm ở đây:
người dùng thật im lặng vài phút rồi bấm liên tiếp mấy cái, `capacity` cho
phép đúng kiểu dùng đó mà vẫn chặn được kẻ gọi không nghỉ.

---

### Câu 8 — Ngân sách theo ngày (CP3)

So sánh hạn mức $30/tháng với hạn mức $1/ngày cho cùng một client. Giả sử có sự
cố khiến một client gọi liên tục từ 2h sáng. Với mỗi cách, thiệt hại tối đa là
bao nhiêu và service tự hồi phục khi nào?

Cùng một tổng tiền $30/tháng, nhưng hai cách chia cho ra hai kịch bản rất khác:

| | $30/tháng | $1/ngày |
|---|---|---|
| Thiệt hại tối đa của sự cố | **$30** | **$1** |
| Client đó bị khóa tới khi nào | tới 00:00 ngày 1 tháng sau | 00:00 UTC hôm sau |
| Thời gian chết tệ nhất | tới ~30 ngày | dưới 24 giờ |
| Ai phải can thiệp | người — phải nâng hạn mức tay | không ai, tự hồi |

Diễn biến sự cố lúc 2h sáng:

**$30/tháng:** không có gì chặn tốc độ tiêu, nên cứ gọi là trừ dần. Nếu sự cố
xảy ra ngày 3 của tháng, đến sáng tôi mất trọn $30 và client đó **không gọi
được nữa suốt 28 ngày còn lại**. Muốn service sống lại thì phải có người thức
dậy, hiểu chuyện gì xảy ra, và nâng hạn mức tay. Nghĩa là một sự cố ban đêm
biến thành một sự cố kéo dài cả tháng, hoặc một cuộc gọi báo động lúc 3h sáng.

**$1/ngày:** key Redis là `spend:<client>:<YYYY-MM-DD>`, nên đến $1 là
`check()` trả 402 và dừng. Tôi mất $1. Sang 00:00 UTC, `today()` sinh ra chuỗi
ngày mới, key mới chưa tồn tại, `spent()` trả `0.0` — **service tự hồi phục,
không ai phải làm gì**. Sáng ra tôi đọc log, thấy đúng client nào, đúng ngày
nào, và sửa nguyên nhân trong giờ hành chính.

Ý chính: hạn mức tháng chỉ báo động **sau khi** tôi đã mất phần lớn số tiền,
còn hạn mức ngày giới hạn thiệt hại của một sự cố xuống 1/30 và biến "sự cố
cần người xử lý gấp" thành "việc xem xét trong giờ làm". Cái tự hồi phục quan
trọng ngang cái giảm tiền: hệ thống nào cần người thức dậy mới sống lại được
thì hệ thống đó chưa xong.

Và rate limit **không** thay thế được cost guard: 10 request/phút nghe an
toàn, nhưng nếu mỗi request nhét 50.000 token thì $1 bay trong vài phút. Một
cái đếm *số lần gọi*, một cái đếm *tiền*.

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Thứ tự sự kiện:

1. **T+0s** — Redis mất kết nối (restart để vá lỗi, hoặc mạng chớp). `ping()`
   bắt đầu trả `False`.
2. **T+0→10s** — cả 3 container đều gọi Redis trong endpoint gộp đó, cả 3 đều
   trả 503. Điểm mấu chốt: chúng **cùng phụ thuộc một Redis**, nên hỏng cùng
   lúc chứ không lần lượt.
3. **T+10→30s** — probe fail đủ số lần `retries`. Vì đây là endpoint
   *liveness*, orchestrator hiểu 503 là "process hỏng, cần restart" và
   **restart cả 3 container cùng lúc**.
4. **T+30s** — Redis quay lại bình thường. Nhưng lúc này cả 3 container đang
   trong quá trình khởi động lại: chưa nạp xong Python, chưa mở port.
   **Không container nào phục vụ được** — số instance sẵn sàng bằng 0.
5. **T+30→60s** — load balancer không có target khỏe nào, mọi request của user
   trả 502/503. Toàn bộ request đang xử lý dở lúc bị restart cũng đứt giữa
   chừng.
6. **Nguy cơ tệ hơn:** cả 3 container khởi động lại cùng lúc nên đồng loạt mở
   kết nối tới Redis vừa hồi — cú dồn đó có thể làm Redis lảo đảo lần nữa,
   probe lại fail, restart lại. Vòng lặp crash, và mỗi vòng lại đồng bộ hóa
   thêm.

Tóm lại: **một sự cố nhỏ 30 giây của một dependency biến thành sự cố toàn hệ
thống kéo dài vài phút, do chính cơ chế tự chữa gây ra.**

Tách hai endpoint thì diễn biến khác hẳn. `/readyz` trả 503 nên load balancer
**ngừng gửi request mới** vào — nhưng `/healthz` vẫn 200 vì nó không chạm
Redis, nên **không container nào bị restart**. 3 container vẫn sống, vẫn giữ
kết nối, vẫn xử lý nốt việc đang làm. Redis quay lại ở T+30s thì `ping()` trả
`True` ngay lần probe kế tiếp, `/readyz` trả 200, load balancer đẩy traffic
lại. Tổng downtime đúng bằng 30 giây của Redis, không nhân lên.

Khác biệt nằm ở chỗ hai endpoint trả lời **hai câu hỏi khác nhau**, và
orchestrator **phản ứng khác nhau** với chúng:

| | `/healthz` (liveness) | `/readyz` (readiness) |
|---|---|---|
| Câu hỏi | Process này còn sống không? | Nhận traffic được chưa? |
| Được kiểm tra dependency | **Không** | **Có** |
| 503 nghĩa là | **restart** container | **ngừng gửi** request, giữ container |

Restart là hành động phá hủy và không đảo ngược được; nó chỉ nên xảy ra khi
vấn đề nằm *trong* process. Redis chết không phải lỗi của process — restart
nó không sửa được gì, chỉ làm mất thêm năng lực phục vụ đúng lúc hệ thống đang
yếu nhất.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Lỗi:** deploy lên Railway, build thành công nhưng deploy fail. Dashboard báo:

```
Attempt #1 failed with service unavailable. Continuing to retry for 19s
Attempt #2 failed with service unavailable. Continuing to retry for 8s
1/1 replicas never became healthy!
```

**Cách tìm nguyên nhân.** Thông báo trên chỉ nói *triệu chứng*: Railway gọi
`/healthz` mà không ai trả lời. Nó không nói vì sao. Điều tôi rút ra được ngay
từ nó là build đã xong — nên lỗi nằm ở lúc **chạy**, không phải lúc **dựng**.

Tôi mở tab **Deploy Logs** (khác **Build Logs** — đây là chỗ tôi suýt tìm
nhầm) và thấy dòng lặp lại nhiều lần:

```
Error: Invalid value for '--port': '$PORT' is not a valid integer.
```

Chuỗi `$PORT` đến uvicorn **nguyên văn 5 ký tự**, không phải rỗng, không phải
một con số. Nghĩa là không có ai nội suy biến môi trường đó.

Đối chiếu với `railway.toml` thì thấy nguyên nhân:

```toml
startCommand = "uvicorn app.main:app --host 0.0.0.0 --port $PORT"
```

Railway chạy `startCommand` dạng **exec**, không qua shell — mà nội suy `$PORT`
là việc của shell. Không có shell thì không ai làm việc đó.

Điều làm tôi lúng túng lúc đầu: `docker compose up` ở máy chạy tốt hoàn toàn.
Lý do là compose dùng `CMD` trong Dockerfile, mà `CMD` của tôi viết là
`["sh", "-c", "uvicorn ... --port ${PORT:-8000}"]` — có `sh -c` nên có shell,
có shell nên `${PORT:-8000}` được nội suy đúng. Còn `startCommand` trong
`railway.toml` thì **ghi đè** `CMD` đó. Bài học: thứ chạy trên cloud có thể
không phải thứ tôi test ở máy, nếu platform có file cấu hình riêng ghi đè.

**Cách sửa.** Bỏ hẳn `startCommand` khỏi `railway.toml` để platform dùng `CMD`
của Dockerfile — chỗ duy nhất định nghĩa lệnh khởi động, và đã xử lý `$PORT`
đúng. Nới thêm `healthcheckTimeout` từ 30 lên 100 để loại nốt khả năng bị cắt
oan lúc khởi động chậm.

**Cách kiểm chứng.** Tôi không đoán mà đo: chạy image ở máy với một cổng lạ
để mô phỏng việc cloud gán cổng bất kỳ.

```bash
docker run -e PORT=9137 -p 9137:9137 day12-chat:porttest
# log: INFO: Uvicorn running on http://0.0.0.0:9137
# curl localhost:9137/healthz → 200 {"status":"ok",...}
```

Phép thử này còn lộ thêm một lỗi thứ hai tôi chưa biết: `HEALTHCHECK` trong
Dockerfile đang hardcode `127.0.0.1:8000`, nên khi cổng khác 8000 thì Docker
báo container `health: starting` mãi không lên `healthy`. Tôi sửa nó đọc
`os.environ.get("PORT", "8000")` giống `CMD`. Railway/Render dùng probe riêng
nên lỗi này không làm deploy fail — nhưng nó vẫn sai, và nếu không thử với
cổng lạ thì tôi đã không phát hiện.

**Kết cục.** Cuối cùng tôi vẫn phải chuyển sang Render, vì Railway hết hạn mức
free và dashboard liên tục "failed to fetch" khi sinh domain. Nhưng bản sửa
`$PORT` không hề bỏ đi: Render cũng tự gán cổng (10000) và cũng dùng `CMD` của
Dockerfile, nên chính bản sửa đó làm service lên xanh ngay lần đầu trên Render
— `/healthz` 200, `/readyz` 200 với `redis: true`, `/chat` không token trả 401.
Đây đúng là điều mà 12-Factor hứa hẹn ở CP1: cùng một image, đổi platform chỉ
là đổi biến môi trường.
