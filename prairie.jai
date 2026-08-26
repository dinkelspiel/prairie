#import "Basic";
#import "Socket";
#import "Hash_Table";

Prairie :: struct {
    socket: Socket;
    address: string;
    port: u16;
}

Http_Method :: enum {
    UNKNOWN;
    GET;
    POST;
}

Http_Protocol :: enum {
    UNKNOWN;
    HTTP_1_0;
    HTTP_1_1;
    HTTP_2;
}

Content_Type :: enum {
    TEXT_HTML;
    APPLICATION_JSON;
    APPLICATION_OCTET_STREAM;
}

MAX_REQUEST_SIZE :: 16 * 1024 * 1024;
MAX_RESPONSE_BODY_SIZE :: 64 * 1024 * 1024;
SOCKET_TIMEOUT_SECONDS :: 5;

Socket_Timeval :: struct {
    seconds: s64;
    microseconds: s64;
}

Http_Header_Field :: struct {
    key: string;
    value: string;
}

Http_Request :: struct {
    method: Http_Method;
    route: string;
    protocol: Http_Protocol;
    headers: [64] Http_Header_Field;
    header_count: s64;
    body: string;
    query_params: Table(string, string);
    form_fields: Table(string, string);
}

Http_Response :: struct {
    status_code: int;
    content_type: Content_Type;
    body: string;
    owned_body: bool;
}

Request_Handler :: #type (request: Http_Request) -> Http_Response;

create :: (address: string, port: u16) -> Prairie, bool {
    if !socket_init() return .{}, false;

    server_socket := socket(AF_INET, .STREAM, .TCP);
    if server_socket == INVALID_SOCKET return .{}, false;

    reuse: s32 = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, *reuse, size_of(s32));

    if bind(server_socket, address, port) == SOCKET_ERROR {
        close_and_reset(*server_socket);
        return .{}, false;
    }

    if listen(server_socket, SOMAXCONN) == SOCKET_ERROR {
        close_and_reset(*server_socket);
        return .{}, false;
    }

    return .{socket = server_socket, address = address, port = port}, true;
}

run :: (prairie: Prairie, handler: Request_Handler) {
    server_socket := prairie.socket;
    defer close_and_reset(*server_socket);

    print("Listening on %:%\n", prairie.address, prairie.port);

    while true {
        client, source := accept(server_socket);
        if client == INVALID_SOCKET {
            error_code := get_last_socket_error();
            print("Accept error: %\n", error_code);
            return;
        }

        handle_client(client, source, handler);
    }
}

handle_client :: (client: Socket, source: sockaddr_in, handler: Request_Handler) {
    defer close_and_reset(*client);

    if !set_socket_timeouts(client) return;

    buffer := alloc_string(MAX_REQUEST_SIZE);
    defer free(buffer);
    request, ok := receive_request(client, buffer);
    defer deinit(*request.query_params);
    defer deinit(*request.form_fields);

    source_text := to_string(source);
    defer free(source_text);

    if !ok {
        print("400 | % | % %\n", source_text, request.method, request.route);
        write_response(client, .{status_code = 400, content_type = .TEXT_HTML, body = "Bad Request"});
        return;
    }

    started_at := seconds_since_init();
    response := handler(request);
    response = sanitize_response(response);
    if !write_response(client, response) print("Send error: %\n", get_last_socket_error());
    if response.owned_body free(response.body);

    duration_ms := (seconds_since_init() - started_at) * 1000.0;
    print("% | % ms | % | % %\n", response.status_code, duration_ms, source_text, request.method, request.route);
}

set_socket_timeouts :: (socket_handle: Socket) -> bool {
    #if OS == .WINDOWS {
        timeout_ms: u32 = SOCKET_TIMEOUT_SECONDS * 1000;
        receive_result := setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO, *timeout_ms, size_of(timeout_ms));
        send_result := setsockopt(socket_handle, SOL_SOCKET, SO_SNDTIMEO, *timeout_ms, size_of(timeout_ms));
    } else {
        timeout := Socket_Timeval.{seconds = SOCKET_TIMEOUT_SECONDS};
        receive_result := setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO, *timeout, size_of(Socket_Timeval));
        send_result := setsockopt(socket_handle, SOL_SOCKET, SO_SNDTIMEO, *timeout, size_of(Socket_Timeval));
    }

    return receive_result != SOCKET_ERROR && send_result != SOCKET_ERROR;
}

receive_request :: (client: Socket, buffer: string) -> Http_Request, bool {
    bytes_read: s64;
    header_end: s64 = -1;

    while header_end < 0 {
        if bytes_read == buffer.count return .{}, false;

        received := recv(client, buffer.data + bytes_read, cast(u64) (buffer.count - bytes_read), cast(MSG) 0);
        if received <= 0 return .{}, false;
        bytes_read += received;

        contents := string_from_bytes(buffer, bytes_read);
        header_end = find_sequence(contents, "\r\n\r\n", 0);
    }

    contents := string_from_bytes(buffer, bytes_read);
    body_start := header_end + 4;
    request, ok := make_request(substring(contents, 0, body_start));
    if !ok return request, false;

    body_length, framing_ok := request_body_length(request);
    if !framing_ok return request, false;
    if body_length > buffer.count - body_start return request, false;

    total_length := body_start + body_length;
    while bytes_read < total_length {
        received := recv(client, buffer.data + bytes_read, cast(u64) (total_length - bytes_read), cast(MSG) 0);
        if received <= 0 return request, false;
        bytes_read += received;
    }

    if bytes_read < total_length return request, false;

    contents = string_from_bytes(buffer, total_length);
    request.body = substring(contents, body_start, total_length);
    if request.method == .POST && request_has_content_type(request, "application/x-www-form-urlencoded") {
        request.form_fields = parse_http_form_fields(request.body);
    }
    return request, true;
}

string_from_bytes :: (buffer: string, count: s64) -> string {
    result: string;
    result.data = buffer.data;
    result.count = count;
    return result;
}

sanitize_response :: (response: Http_Response) -> Http_Response {
    if response.status_code < 100 || response.status_code > 599 return .{status_code = 500, content_type = .TEXT_HTML, body = "Internal Server Error"};
    if response.body.count < 0 || response.body.count > MAX_RESPONSE_BODY_SIZE return .{status_code = 500, content_type = .TEXT_HTML, body = "Internal Server Error"};
    return response;
}

write_response :: (client: Socket, response: Http_Response) -> bool {
    safe_response := sanitize_response(response);
    header := sprint(
        "HTTP/1.1 % %\r\nContent-Type: %\r\nContent-Length: %\r\nConnection: close\r\n\r\n",
        safe_response.status_code,
        status_text(safe_response.status_code),
        content_type_to_string(safe_response.content_type),
        safe_response.body.count
    );
    defer free(header);

    if !send_all(client, header) return false;
    if safe_response.body.count > 0 && !send_all(client, safe_response.body) return false;
    return true;
}

send_all :: (socket_handle: Socket, data: string) -> bool {
    sent: s64;
    while sent < data.count {
        written := send(socket_handle, data.data + sent, cast(u64) (data.count - sent), cast(MSG) 0);
        if written <= 0 return false;
        sent += written;
    }
    return true;
}

status_text :: (status_code: int) -> string {
    if status_code == 200 return "OK";
    if status_code == 400 return "Bad Request";
    if status_code == 401 return "Unauthorized";
    if status_code == 408 return "Request Timeout";
    if status_code == 404 return "Not Found";
    if status_code == 413 return "Content Too Large";
    if status_code == 431 return "Request Header Fields Too Large";
    if status_code == 500 return "Internal Server Error";
    return "Status";
}

content_type_to_string :: (content_type: Content_Type) -> string {
    if content_type == .TEXT_HTML return "text/html";
    if content_type == .APPLICATION_JSON return "application/json";
    return "application/octet-stream";
}

make_request :: (contents: string) -> Http_Request, bool {
    if contents.count < 4 || find_sequence(contents, "\r\n\r\n", 0) != contents.count - 4 return .{}, false;

    first_line_end := find_sequence(contents, "\r\n", 0);
    if first_line_end < 0 return .{}, false;

    request, ok := parse_http_request_line(substring(contents, 0, first_line_end));
    if !ok return request, false;

    cursor := first_line_end + 2;
    while cursor <= contents.count {
        line_end := find_sequence(contents, "\r\n", cursor);
        if line_end < 0 line_end = contents.count;
        if line_end == cursor {
            request.query_params = parse_http_query_params(request.route);
            return request, true;
        }
        if request.header_count == request.headers.count return request, false;

        line := substring(contents, cursor, line_end);
        colon := find_byte(line, #char ":", 0);
        if colon <= 0 return request, false;

        key := substring(line, 0, colon);
        if !valid_header_name(key) return request, false;

        value_start := colon + 1;
        while value_start < line.count && is_optional_whitespace(line[value_start]) value_start += 1;
        value_end := line.count;
        while value_end > value_start && is_optional_whitespace(line[value_end - 1]) value_end -= 1;

        value := substring(line, value_start, value_end);
        if !valid_header_value(value) return request, false;

        request.headers[request.header_count] = .{
            key = key,
            value = value
        };
        request.header_count += 1;

        if line_end == contents.count break;
        cursor = line_end + 2;
    }

    if request.protocol == .HTTP_1_1 {
        host_count: s64;
        for index: 0..request.header_count-1 {
            if equal_ascii_case_insensitive(request.headers[index].key, "Host") {
                if request.headers[index].value.count == 0 return request, false;
                host_count += 1;
            }
        }
        if host_count != 1 return request, false;
    }

    request.query_params = parse_http_query_params(request.route);

    return request, true;
}

parse_http_query_params :: (route: string) -> Table(string, string) {
    split_route        := split(route, "?");
    if split_route.count == 1 return .{};
    
    after_questionmark := split_route[1];
    return parse_http_fields(after_questionmark);
}

parse_http_form_fields :: (body: string) -> Table(string, string) {
    return parse_http_fields(body);
}

parse_http_fields :: (contents: string) -> Table(string, string) {
    fields: Table(string, string);
    if contents.count == 0 return fields;

    raw_fields := split(contents, "&");

    for raw_fields {
        separator := find_byte(it, #char "=", 0);
        if separator < 0 continue;

        key := substring(it, 0, separator);
        value := substring(it, separator + 1, it.count);
        table_set(*fields, key, value);
    }

    return fields;
}

request_has_content_type :: (request: Http_Request, expected: string) -> bool {
    for index: 0..request.header_count-1 {
        header := request.headers[index];
        if !equal_ascii_case_insensitive(header.key, "Content-Type") continue;

        separator := find_byte(header.value, #char ";", 0);
        value_end := ifx separator < 0 then header.value.count else separator;
        return equal_ascii_case_insensitive(substring(header.value, 0, value_end), expected);
    }
    return false;
}

parse_http_request_line :: (line: string) -> Http_Request, bool {
    request: Http_Request;

    first_space := find_byte(line, #char " ", 0);
    if first_space < 0 return request, false;

    second_space := find_byte(line, #char " ", first_space + 1);
    if second_space < 0 return request, false;

    request.route = substring(line, first_space + 1, second_space);
    if find_byte(line, #char " ", second_space + 1) >= 0 return request, false;

    method_text := substring(line, 0, first_space);
    protocol_text := substring(line, second_space + 1, line.count);

    if method_text == "GET" request.method = .GET;
    else if method_text == "POST" request.method = .POST;
    else return request, false;

    if protocol_text == "HTTP/1.0" request.protocol = .HTTP_1_0;
    else if protocol_text == "HTTP/1.1" request.protocol = .HTTP_1_1;
    else return request, false;

    return request, true;
}

request_body_length :: (request: Http_Request) -> s64, bool {
    content_length: s64;
    has_content_length := false;

    for index: 0..request.header_count-1 {
        header := request.headers[index];
        if equal_ascii_case_insensitive(header.key, "Transfer-Encoding") return 0, false;
        if !equal_ascii_case_insensitive(header.key, "Content-Length") continue;
        if has_content_length return 0, false;

        ok: bool;
        content_length, ok = parse_nonnegative_decimal(header.value);
        if !ok return 0, false;
        has_content_length = true;
    }

    return content_length, true;
}

parse_nonnegative_decimal :: (text: string) -> s64, bool {
    if text.count == 0 return 0, false;

    value: s64;
    for byte: text {
        if byte < #char "0" || byte > #char "9" return 0, false;
        digit := cast(s64) (byte - #char "0");
        if value > (9223372036854775807 - digit) / 10 return 0, false;
        value = value * 10 + digit;
    }
    return value, true;
}

equal_ascii_case_insensitive :: (left: string, right: string) -> bool {
    if left.count != right.count return false;
    for index: 0..left.count-1 {
        if ascii_lower(left[index]) != ascii_lower(right[index]) return false;
    }
    return true;
}

ascii_lower :: (byte: u8) -> u8 {
    if byte >= #char "A" && byte <= #char "Z" return byte + (#char "a" - #char "A");
    return byte;
}

is_optional_whitespace :: (byte: u8) -> bool {
    return byte == #char " " || byte == #char "\t";
}

valid_header_name :: (name: string) -> bool {
    for byte: name {
        if byte >= #char "a" && byte <= #char "z" continue;
        if byte >= #char "A" && byte <= #char "Z" continue;
        if byte >= #char "0" && byte <= #char "9" continue;
        if byte == #char "!" || byte == #char "#" || byte == #char "$" || byte == #char "%" continue;
        if byte == #char "&" || byte == #char "'" || byte == #char "*" || byte == #char "+" continue;
        if byte == #char "-" || byte == #char "." || byte == #char "^" || byte == #char "_" continue;
        if byte == #char "`" || byte == #char "|" || byte == #char "~" continue;
        return false;
    }
    return true;
}

valid_header_value :: (value: string) -> bool {
    for byte: value {
        if byte == #char "\t" continue;
        if byte < 0x20 || byte == 0x7f return false;
    }
    return true;
}

find_byte :: (text: string, value: u8, start: s64) -> s64 {
    index := start;
    while index < text.count {
        if text[index] == value return index;
        index += 1;
    }
    return -1;
}

find_sequence :: (text: string, sequence: string, start: s64) -> s64 {
    if sequence.count == 0 return start;
    index := start;
    while index + sequence.count <= text.count {
        matched := true;
        offset: s64;
        while offset < sequence.count {
            if text[index + offset] != sequence[offset] {
                matched = false;
                break;
            }
            offset += 1;
        }
        if matched return index;
        index += 1;
    }
    return -1;
}

substring :: (text: string, start: s64, end: s64) -> string {
    assert(start >= 0 && start <= end && end <= text.count);
    result := text;
    result.data += start;
    result.count = end - start;
    return result;
}