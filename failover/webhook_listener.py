#!/usr/bin/env python3
import http.server, subprocess, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers['Content-Length'])
        body = json.loads(self.rfile.read(length))
        for alert in body.get("alerts", []):
            if alert.get("labels", {}).get("alertname") == "AppDown" and alert.get("status") == "firing":
                subprocess.run(["/opt/devops-infra/failover/failover.sh"])
        self.send_response(200)
        self.end_headers()

http.server.HTTPServer(('localhost', 9095), Handler).serve_forever()
