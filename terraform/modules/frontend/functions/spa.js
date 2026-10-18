function handler(event) {
    var request = event.request;
    var uri = request.uri;
    // Defense in depth: this function is associated with the S3 default behavior only.
    if (uri === '/api' || uri.indexOf('/api/') === 0) {
        return request;
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
        return request;
    }
    if (uri.indexOf('/assets/') === 0 || uri.indexOf('/brand/') === 0) {
        return request;
    }
    var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
    if (lastSegment.indexOf('.') === -1) {
        request.uri = '/index.html';
    }
    return request;
}
