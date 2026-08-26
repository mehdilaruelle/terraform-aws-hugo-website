    // A viewer-request function can answer instead of forwarding, so the
    // redirect costs no origin fetch. Terraform substitutes the apex.
    var apex = '__APEX__';
    var host = request.headers.host && request.headers.host.value;
    if (host && host.toLowerCase() === 'www.' + apex) {
        // multiValue holds every value of a repeated parameter; value holds
        // only the first. CloudFront cannot tell 'foo' from 'foo=', so both
        // come back as 'foo='.
        var qs = '';
        for (var k in request.querystring) {
            var field = request.querystring[k];
            var values = field.multiValue || [field];
            for (var i = 0; i < values.length; i++) {
                qs += (qs ? '&' : '?') + k + '=' + values[i].value;
            }
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
