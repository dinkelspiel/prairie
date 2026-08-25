#load "module.jai";

#import "Basic";

main :: () {
    app, ok := create("0.0.0.0", 8010);
    if !ok {
        print("Failed creating server\n");
        return;
    }

    router := create_router();
    defer destroy_router(*router);

    get(*router, "/", (request: Http_Request) -> Http_Response {
        return .{
            status_code = 200,
            body = "index",
            content_type = .TEXT_HTML
        };
    });

    middleware(*router, (router: *Router) {
        middleware(router, (nested_router: *Router) {
            get(nested_router, "/test", (request: Http_Request) -> Http_Response {
                return .{
                    status_code = 200,
                    body = "test",
                    content_type = .TEXT_HTML
                };
            });
        }, test);

        get(router, "/api", (request: Http_Request) -> Http_Response {
            return .{
                status_code = 200,
                body = "{\"test\": \"test\"}",
                content_type = .APPLICATION_JSON
            };
        });
    }, authenticated);

    run(app, handle_request(*router));
}

authenticated :: (request: Http_Request) -> Middleware_Response {
    if request.route == "/api" return respond(.{status_code = 400});
    return next();
}

test :: (request: Http_Request) -> Middleware_Response {
    if request.route == "/test" return respond(.{status_code = 500});
    return next();
}
