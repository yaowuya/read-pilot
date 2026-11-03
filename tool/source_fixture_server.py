import argparse
import html
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

TITLE = "月下的书页"
PARAGRAPHS = [
    "夜色落下来之后，房间里只留了一盏灯。窗外的声音渐渐远去，书页上的字却慢慢清晰起来。",
    "读书并不总是为了寻找一个答案。有时候，我们只是希望在一天结束的时候，找回一点不被打扰的时间。",
    "书桌上放着一杯温水。没有消息提示，没有需要立即完成的任务。下一页，还可以等我们把这一页读完。",
    "纸上的远方不需要车票。一个人的经历，可以从另一位读者的眼睛里重新开始。",
    "遇见喜欢的句子，就把它记下来。很久以后再次读到，也许会想起此时的灯光，和窗外的一小片月色。",
    "重要的不是读得有多快，而是有没有真的看见那些文字。停一停，也是一种向前。",
    "这段文字由阅读编写，只用于验证书源的搜索、目录、正文与离线缓存，不来自商业出版物。",
    "当我们把书合上，故事不会就此消失。它留在记忆里，也留在下一次翻开书页的动作里。",
]

class Handler(BaseHTTPRequestHandler):
    def _send(self, body, content_type="text/html; charset=utf-8", status=200):
        data = body.encode("utf-8")
        self.send_response(status)
        origin = self.headers.get("Origin", "")
        if origin in ("http://localhost:4173", "http://127.0.0.1:4173", "http://localhost:5173", "http://127.0.0.1:5173"):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in ("/", "/search"):
            query = parse_qs(url.query).get("q", [""])[0]
            match = not query or query in TITLE or query in "阅读阅读"
            self._send('<main><div class="book"><a href="/book/1">月下的书页</a><span class="author">阅读</span><p class="intro">本地书源验证用原创文本。</p></div></main>' if match else '<main>没有匹配的书籍</main>')
        elif url.path == "/book/1":
            self._send('<h1>月下的书页</h1><p class="intro">本地书源验证用原创文本。</p><a class="toc" href="/toc/1">查看目录</a>')
        elif url.path == "/toc/1":
            self._send('<div id="chapters"><a href="/chapter/1">第一章 一盏灯</a><a href="/chapter/2">第二章 另一页</a></div>')
        elif url.path in ("/chapter/1", "/chapter/2"):
            paragraphs = PARAGRAPHS if url.path.endswith("1") else list(reversed(PARAGRAPHS))
            self._send('<article>' + ''.join('<p>' + html.escape(text) + '</p>' for text in paragraphs) + '</article>')
        elif url.path == "/source.json":
            self._send(Path(__file__).resolve().parents[1].joinpath('examples/book-source.json').read_text(encoding='utf-8'), 'application/json; charset=utf-8')
        else:
            self._send('Not found', status=404)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Local-only book-source fixture for 阅读 verification.')
    parser.add_argument('--port', type=int, default=8766)
    args = parser.parse_args()
    print('阅读 source fixture: http://127.0.0.1:' + str(args.port), flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
