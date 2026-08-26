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

Route :: struct {
    path: string;
    method: Http_Method;
    middlewares: [8] Middleware_Handler;
    middleware_count: s64;
    handler: Request_Handler;
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

    for index: 0..router.route_count-1 {
        route := *router.routes[index];
        if route.path != split(request.route, "?")[0] || route.method != request.method continue;

        for middleware_index: 0..route.middleware_count-1 {
            result := route.middlewares[middleware_index](request);
            if result.status == .RESPOND return result.response;
        }

        return route.handler(request);
    }

    return .{status_code = 404, content_type = .TEXT_HTML, body = "Not Found"};
}

add_route :: (router: *Router, path: string, method: Http_Method, handler: Request_Handler) {
    assert(router.route_count < router.routes.count, "Router supports at most % routes", router.routes.count);

    route := *router.routes[router.route_count];
    route.path = path;
    route.method = method;
    route.handler = handler;
    route.middleware_count = router.active_middleware_count;

    for index: 0..route.middleware_count-1 route.middlewares[index] = router.active_middlewares[index];
    router.route_count += 1;
}

get :: (router: *Router, path: string, handler: Request_Handler) {
    add_route(router, path, .GET, handler);
}

post :: (router: *Router, path: string, handler: Request_Handler) {
    add_route(router, path, .POST, handler);
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
