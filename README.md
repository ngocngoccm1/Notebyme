# Notes

Đăng nhập bằng tên đăng nhập và mật khẩu đúng 4 chữ số. Tạo tài khoản là dùng ngay, không nhập email và không có bước xác nhận.

Ứng dụng ghi chú với frontend trên GitHub Pages và backend trên Supabase Edge Functions. Không cần thuê thêm host Node.js.

## Cấu trúc

- index.html: chỉ giao diện, không có key, token hay JavaScript inline.
- assets/: giao diện, API client và lưu nháp trên thiết bị. config.js chỉ chứa địa chỉ backend công khai.
- admin/logs/: trang đăng nhập quản trị và xem nhật ký backend.
- supabase/functions/notebyme-api/: đăng nhập, phiên làm việc, ghi chú, log và kiểm soát truy cập.
- schema.sql và backend-schema.sql: bảng ghi chú, bảng backend, RLS và quyền truy cập.
- .github/workflows/pages.yml: kiểm thử rồi chỉ triển khai file frontend.

## Bảo mật

Supabase API key, access token và refresh token không được gửi về frontend. Backend dùng biến môi trường do Supabase cấp. Token Supabase được mã hóa AES-GCM trước khi lưu trong bảng backend_sessions. Các bảng backend chặn anon/authenticated bằng cả quyền SQL và RLS. Truy cập ghi chú vẫn chạy bằng quyền người dùng đã được Supabase xác minh, không dùng service_role để bỏ qua quyền sở hữu.

Trình duyệt giữ mã phiên ngẫu nhiên của ứng dụng trong sessionStorage theo từng tab. Mã này vẫn là thông tin xác thực của phiên hiện tại, phải được bảo vệ; nó không phải Supabase JWT hay API key. Backend chỉ lưu hash của mã phiên. Phiên người dùng hết hạn sau 12 giờ; phiên quản trị sau 1 giờ. Đóng tab sẽ kết thúc phiên trên trình duyệt.

Trang log có mật khẩu quản trị riêng, được lưu dưới dạng PBKDF2 hash ở backend. Mật khẩu khởi tạo nằm trong file .env cục bộ, đã bị Git bỏ qua. Không commit hoặc upload file này lên GitHub.

Log chỉ ghi sự kiện, mã lỗi, HTTP status, thời gian xử lý và request ID. Không ghi email, mật khẩu, header, mã phiên, token, stack trace hay nội dung ghi chú. Log cũ hơn 14 ngày được dọn khi có lưu lượng. Mọi lỗi frontend hiển thị mã request để tra cứu.

## Thiết lập project mới

1. Chạy schema.sql rồi backend-schema.sql trong Supabase SQL Editor.
2. Thêm cấu hình allowed_origins trong backend_settings, dạng mảng JSON các origin chính xác được phép gọi API. Ví dụ: https://YOUR_USERNAME.github.io. CORS không thay thế kiểm tra phiên đăng nhập.
3. Chạy node scripts/create-admin.mjs để tạo mật khẩu quản trị trong .env và SQL khởi tạo trong .data/admin-bootstrap.sql. Chạy SQL đó trong SQL Editor.
4. Triển khai thư mục supabase/functions/notebyme-api bằng Supabase CLI hoặc dashboard. Function tự kiểm tra mã phiên ứng dụng nên verify_jwt=false được đặt trong supabase/config.toml. Không bật Data API công khai cho các bảng backend.
5. Đặt API_URL trong assets/config.js bằng URL function vừa triển khai. Đây là URL công khai, không phải secret. Cập nhật connect-src trong CSP của index.html và admin/logs/index.html nếu đổi project.
6. Trong GitHub Settings > Pages, chọn Source: GitHub Actions. Workflow chỉ upload index.html, assets, admin và sw.js; không đưa file backend hoặc cấu hình riêng lên Pages.

Các biến server SUPABASE_URL, SUPABASE_ANON_KEY và SUPABASE_SERVICE_ROLE_KEY được Supabase Edge Functions cấp sẵn. Không chép chúng vào frontend. Backend tạo danh tính nội bộ đã xác nhận sẵn; không gửi email. PIN được biến đổi bằng HMAC với pepper riêng ở backend trước khi đưa vào Supabase Auth. Giới hạn 5 lần thử sai cho mỗi tên đăng nhập trong 15 phút.

## Kiểm tra và chạy frontend cục bộ

Yêu cầu Node.js 22.12+ để chạy test và Python 3 để phục vụ frontend.

~~~sh
npm ci
npm test
npm run dev
~~~

Thêm origin http://127.0.0.1:3000 vào allowed_origins khi thử cục bộ; bỏ origin phát triển khi không còn cần. Backend thật phải được triển khai riêng trên Supabase.

## Giới hạn

- Ghi chú lưu nháp ở localStorage không được mã hóa đầu cuối. Chưa dùng cho mật khẩu hay khóa bí mật.
- Đăng xuất sẽ xóa cache ghi chú của tài khoản trên thiết bị; nếu còn thay đổi chưa đồng bộ, ứng dụng hỏi trước.
- Khi phiên hết hạn, bản nháp còn lại để người dùng đăng nhập lại đúng tài khoản và tiếp tục đồng bộ.
- Sửa một ghi chú trên nhiều thiết bị vẫn có thể ghi đè theo lần đồng bộ cuối; chưa có lịch sử phiên bản.
- Đã sửa lỗi mất thay đổi trong lúc upload, lẫn response khi đổi tài khoản và mất cache khi response không chứa đủ ghi chú.
- Backend phân trang theo id, tải tối đa 50.000 ghi chú; vượt mức sẽ báo lỗi, không âm thầm cắt dữ liệu.
