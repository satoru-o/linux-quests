import secrets

from flask import Flask

app = Flask(__name__)

# FLAGはプロセス起動時にメモリ上でランダム生成される。ソースにもファイルにも固定値では存在しない。
FLAG = f"FLAG{{{secrets.token_hex(16)}}}"


@app.get("/flag")
def flag():
    return FLAG


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
