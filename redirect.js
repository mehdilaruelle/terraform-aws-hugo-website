function handler(event) {
    var request = event.request;

    // A viewer-request function can answer instead of forwarding, so the
    // redirect costs no origin fetch. Terraform substitutes the apex.
    var apex = '__APEX__';
    if (apex) {
        var host = request.headers.host && request.headers.host.value;
        if (host && host.toLowerCase() === 'www.' + apex) {
            var qs = '';
            for (var k in request.querystring) {
                qs += (qs ? '&' : '?') + k;
                if (request.querystring[k].value) qs += '=' + request.querystring[k].value;
            }
            return {
                statusCode: 301,
                statusDescription: 'Moved Permanently',
                headers: {
                    location: { value: 'https://' + apex + request.uri + qs },
                    'cache-control': { value: 'max-age=3600' }
                }
            };
        }
    }

    // Source: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/example-function-add-index.html
    var uri = request.uri;

    // Check whether the URI is missing a file name.
    if (uri.endsWith('/')) {
        request.uri += 'index.html';
    }
    // Check whether the URI is missing a file extension.
    else if (!uri.includes('.')) {
        request.uri += '/index.html';
    }

    return request;
}
