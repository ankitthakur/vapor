extension Application: Responder {
    /**
        Returns a response to the given request

        - parameter request: received request
        - throws: error if something fails in finding response
        - returns: response if possible
    */
    public func respond(to request: Request) throws -> Response {
        log.info("\(request.method) \(request.uri.path ?? "/")")

        var responder: Responder
        let request = request

        /*
         The HEAD method is identical to GET.

         https://tools.ietf.org/html/rfc2616#section-9.4
         */
        let originalMethod = request.method
        if case .head = request.method {
            request.method = .get
        }


        // Check in routes
        if let handler = router.route(request) {
            responder = handler
        } else if let fileHander = self.checkFileSystem(for: request) {
            responder = fileHander
        } else {
            // Default not found handler
            responder = Request.Handler { _ in
                let normal: [Method] = [.get, .post, .put, .patch, .delete]

                if normal.contains(request.method) {
                    throw Abort.notFound
                } else if case .options = request.method {
                    return Response(status: .ok, headers: [
                        "Allow": "OPTIONS"
                        ])
                } else {
                    return Response(status: .notImplemented)
                }
            }
        }

        // Loop through middlewares in order
        responder = self.globalMiddleware.chain(to: responder)

        var response: Response
        do {
            response = try responder.respond(to: request)

            if response.headers["Content-Type"] == nil {
                log.warning("Response had no 'Content-Type' header.")
            }
        } catch {
            var error = "Server Error: \(error)"
            if config.environment == .production {
                error = "Something went wrong"
            }
            response = Response(status: .internalServerError, body: error.bytes)
        }

        response.headers["Server"] = "Vapor \(Vapor.VERSION)"

        /**
         The server MUST NOT return a message-body in the response for HEAD.

         https://tools.ietf.org/html/rfc2616#section-9.4
         */
        if case .head = originalMethod {
            // TODO: What if body is set to chunked¿?
            response.body = .data([])
        }
        
        return response
    }
}
