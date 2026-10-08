#import "Basic";
#import "String"; 

Middleware_Status :: enum {
    NEXT;
    RESPOND;
}

Middleware_Response :: struct {
    status: Middleware_Status;
    response: Http_Response;
}

Middleware_Handler :: #type (request: Http_Request) -> Middleware_Response;
Route_Group :: #type (router: *Router);
Route_Handler :: #type (request: Http_Request, params: [] string) -> Http_Response;

MAX_ROUTE_PARAMS :: 8;

Route :: struct {
    path: string;
    method: Http_Method;
    middlewares: [8] Middleware_Handler;
    middleware_count: s64;
    handler: Route_Handler;
}

Router :: struct {
    active_middlewares: [8] Middleware_Handler;
    active_middleware_count: s64;
    routes: [64] Route;
    route_count: s64;
}

global_router: *Router;

next :: () -> Middleware_Response {
    return .{status = .NEXT};
}

respond :: (response: Http_Response) -> Middleware_Response {
    return .{status = .RESPOND, response = response};
}

create_router :: () -> Router {
    return .{};
}

destroy_router :: (router: *Router) {
    router.* = .{};
}

handle_request :: (router: *Router) -> Request_Handler {
    global_router = router;
    return route_request;
}

route_request :: (request: Http_Request) -> Http_Response {
    router := global_router;
    if !router return .{status_code = 500};

    path := request.route;
    query := find_byte(path, #char "?", 0);
    if query >= 0 then path = substring(path, 0, query);

    for index: 0..router.route_count-1 {
        route := *router.routes[index];
        if route.method != request.method continue;
        params: [MAX_ROUTE_PARAMS] string;
        param_count, matched := route_matches(route.path, path, params);
        if !matched continue;

        for middleware_index: 0..route.middleware_count-1 {
            result := route.middlewares[middleware_index](request);
            if result.status == .RESPOND return result.response;
        }

        return route.handler(request, array_view(params, 0, param_count));
    }

    return .{status_code = 404, content_type = .TEXT_HTML, body = "Not Found"};
}

route_matches :: (pattern: string, path: string, params: [] string) -> s64, bool {
    count: s64;
    pattern_cursor, path_cursor: s64;
    while true {
        pattern_end := find_byte(pattern, #char "/", pattern_cursor);
        if pattern_end < 0 then pattern_end = pattern.count;
        path_end := find_byte(path, #char "/", path_cursor);
        if path_end < 0 then path_end = path.count;

        expected := substring(pattern, pattern_cursor, pattern_end);
        actual := substring(path, path_cursor, path_end);
        if expected.count && expected[0] == #char ":" {
            _, type := route_param(expected);
            if !actual.count || count == params.count return 0, false;
            if type == "int" {
                _, ok := parse_nonnegative_decimal(actual);
                if !ok return 0, false;
            }
            params[count] = actual;
            count += 1;
        } else if expected != actual {
            return 0, false;
        }

        if (pattern_end == pattern.count) != (path_end == path.count) return 0, false;
        if pattern_end == pattern.count return count, true;
        pattern_cursor = pattern_end + 1;
        path_cursor = path_end + 1;
    }
    return 0, false;
}

route_param :: (segment: string) -> name: string, type: string {
    name := substring(segment, 1, segment.count);
    comma := find_byte(name, #char ",", 0);
    if comma < 0 return name, "string";
    return substring(name, 0, comma), substring(name, comma + 1, name.count);
}

route_int :: (text: string) -> int {
    value := parse_nonnegative_decimal(text);
    return value;
}

route_handler :: ($path: string, $handler: $H) -> Route_Handler {
    return (request: Http_Request, params: [] string) -> Http_Response {
        #insert #run route_call(path);
    };
}

route_call :: (path: string) -> string {
    builder: String_Builder;
    append(*builder, "return handler(request");
    count: s64;
    cursor: s64;
    while cursor <= path.count {
        end := find_byte(path, #char "/", cursor);
        if end < 0 then end = path.count;
        segment := substring(path, cursor, end);
        if segment.count && segment[0] == #char ":" {
            name, type := route_param(segment);
            assert(name.count > 0, "Route % has an unnamed parameter", path);
            assert(count < MAX_ROUTE_PARAMS, "Route % has more than % parameters", path, MAX_ROUTE_PARAMS);
            if type == "int" then print_to_builder(*builder, ", % = route_int(params[%])", name, count);
            else if type == "string" then print_to_builder(*builder, ", % = params[%]", name, count);
            else assert(false, "Route % uses unknown parameter type '%'", path, type);
            count += 1;
        }
        cursor = end + 1;
    }
    append(*builder, ");");
    return builder_to_string(*builder);
}

add_route :: (router: *Router, path: string, method: Http_Method, handler: Route_Handler) {
    assert(router.route_count < router.routes.count, "Router supports at most % routes", router.routes.count);

    route := *router.routes[router.route_count];
    route.path = path;
    route.method = method;
    route.handler = handler;
    route.middleware_count = router.active_middleware_count;

    for index: 0..route.middleware_count-1 route.middlewares[index] = router.active_middlewares[index];
    router.route_count += 1;
}

get :: (router: *Router, $path: string, $handler: $H) {
    add_route(router, path, .GET, route_handler(path, handler));
}

post :: (router: *Router, $path: string, $handler: $H) {
    add_route(router, path, .POST, route_handler(path, handler));
}

middleware :: (router: *Router, routes: Route_Group, middlewares: .. Middleware_Handler) {
    assert(router.active_middleware_count + middlewares.count <= router.active_middlewares.count, "Router supports at most % active middlewares", router.active_middlewares.count);

    for item: middlewares {
        router.active_middlewares[router.active_middleware_count] = item;
        router.active_middleware_count += 1;
    }

    routes(router);

    router.active_middleware_count -= middlewares.count;
}
