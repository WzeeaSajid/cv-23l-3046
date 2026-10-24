import base64
import json
import os
import time

import boto3

s3 = boto3.client("s3")

# Bucket name and prefix come from environment variables, not the code
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

FILES = {
    "/": ("index.html", "text/html"),
    "/index.html": ("index.html", "text/html"),
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}


def respond(status, body, content_type, extra_headers=None, binary=False):
    headers = {"Content-Type": content_type}
    if extra_headers:
        headers.update(extra_headers)
    return {
        "statusCode": status,
        "headers": headers,
        "body": base64.b64encode(body).decode("ascii") if binary else body,
        "isBase64Encoded": binary,
    }


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")

    if path in FILES:
        name, content_type = FILES[path]
        try:
            obj = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)
            data = obj["Body"].read()
            if name == "index.html":
                html = data.decode("utf-8").replace(
                    "{{HOSTED_ON}}", "Lambda " + context.function_name)
                response = respond(200, html, "text/html",
                                   {"Cache-Control": "max-age=60"})
            elif name == "cv.pdf":
                response = respond(200, data, content_type, binary=True)
            else:
                response = respond(200, data.decode("utf-8"), content_type)
        except Exception as exc:
            print("error:", repr(exc))
            response = respond(500, "<h1>500 Server error</h1>", "text/html")
    else:
        response = respond(404, "<h1>404 Not Found</h1><p>No such page.</p>",
                           "text/html")

    print(json.dumps({
        "fn": context.function_name,
        "path": path,
        "status": response["statusCode"],
        "ms": int((time.time() - start) * 1000),
    }))
    return response