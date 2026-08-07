import http.server
import secrets
import socketserver

PORT = 8080

# FLAGはここで毎回ランダムに生成する。ソースコードのどこにも固定値としては存在しない。
with open("flag.txt", "w") as f:
    f.write(f"FLAG{{{secrets.token_hex(16)}}}\n")

Handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.serve_forever()
