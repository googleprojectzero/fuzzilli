#!/usr/bin/env python3

import argparse
import time
import re
from collections import deque
from html.parser import HTMLParser
from pathlib import Path
from typing import Set, Deque, Tuple
from urllib.parse import urljoin, urlparse, urlunparse, urlsplit, urlunsplit, urlencode, parse_qsl
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from urllib import robotparser


START_URL_DEFAULT = "https://devdocs.io/cpp"
ALLOWED_PATH_PREFIX = "/cpp"


class LinkExtractor(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__()
        self.base_url = base_url
        self.links: Set[str] = set()

    def handle_starttag(self, tag: str, attrs):
        if tag != "a":
            return
        for (attr, value) in attrs:
            if attr == "href" and value:
                url = value.strip()
                if url.startswith("javascript:") or url.startswith("mailto:") or url.startswith("tel:"):
                    continue
                joined = urljoin(self.base_url, url)
                self.links.add(joined)


def normalize_url(raw_url: str) -> str:
    parts = list(urlsplit(raw_url))
    parts[3] = ""  # drop fragment
    if parts[3]:
        q = parse_qsl(parts[3], keep_blank_values=True)
        q.sort()
        parts[3] = urlencode(q)
    return urlunsplit(parts)


def is_same_site(url: str, root_netloc: str) -> bool:
    netloc = urlsplit(url).netloc
    return netloc == root_netloc


def is_allowed_path(url: str) -> bool:
    parsed = urlsplit(url)
    path = parsed.path
    return path.startswith(ALLOWED_PATH_PREFIX) or path == "/" or path == "/cpp.html"


def is_probably_html(content_type: str) -> bool:
    if not content_type:
        return False
    return "text/html" in content_type or "application/xhtml+xml" in content_type


def path_for_url(url: str, base_out: Path) -> Path:
    parsed = urlparse(url)
    path = parsed.path
    if not path or path.endswith("/"):
        path = (path.rstrip("/") + "/index.html") if path else "/index.html"
    else:
        if not re.search(r"\.[A-Za-z0-9]{1,6}$", path):
            path = f"{path}.html"

    query = parsed.query
    if query:
        safe_query = re.sub(r"[^A-Za-z0-9._-]", "_", query)
        p = Path(path)
        path = str(p.with_name(p.stem + f"__{safe_query}" + p.suffix))

    return base_out / parsed.netloc / path.lstrip("/")


def fetch(url: str, user_agent: str, timeout: float) -> Tuple[bytes, str]:
    req = Request(url, headers={"User-Agent": user_agent, "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"})
    with urlopen(req, timeout=timeout) as resp:
        content_type = resp.headers.get("Content-Type", "")
        data = resp.read()
        return data, content_type


def crawl(start_url: str, out_dir: Path, max_pages: int, delay_s: float, user_agent: str, timeout_s: float) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    root = urlsplit(start_url)
    root_netloc = root.netloc

    rp = robotparser.RobotFileParser()
    rp.set_url(urlunsplit((root.scheme, root.netloc, "/robots.txt", "", "")))
    try:
        rp.read()
    except Exception:
        pass

    seen: Set[str] = set()
    q: Deque[str] = deque([start_url])
    pages_fetched = 0

    while q and (max_pages <= 0 or pages_fetched < max_pages):
        url = q.popleft()
        url = normalize_url(url)
        if url in seen:
            continue
        seen.add(url)

        if not is_same_site(url, root_netloc) or not is_allowed_path(url):
            continue

        if not rp.can_fetch(user_agent, url):
            continue

        try:
            data, content_type = fetch(url, user_agent=user_agent, timeout=timeout_s)
        except HTTPError:
            continue
        except URLError:
            continue
        except Exception:
            continue

        if not is_probably_html(content_type):
            continue

        out_path = path_for_url(url, out_dir)
        try:
            if not out_path.parent.exists():
                out_path.parent.mkdir(parents=True)
            out_path.write_bytes(data)
            pages_fetched += 1
        except (FileExistsError, OSError):
            pass
        except Exception:
            pass

        try:
            extractor = LinkExtractor(base_url=url)
            extractor.feed(data.decode("utf-8", errors="ignore"))
            for link in extractor.links:
                norm = normalize_url(link)
                if norm not in seen and is_same_site(norm, root_netloc) and is_allowed_path(norm):
                    q.append(norm)
        except Exception:
            pass

        if delay_s > 0:
            time.sleep(delay_s)


def default_output_dir() -> Path:
    here = Path(__file__).resolve()
    return here.parent


def main():
    parser = argparse.ArgumentParser(description="Crawl devdocs.io C++ docs into a local folder.")
    parser.add_argument("start_url", nargs="?", default=START_URL_DEFAULT, help=f"Start URL (default: {START_URL_DEFAULT})")
    parser.add_argument("--out", dest="out", default=str(default_output_dir()), help="Output directory (default: <repo>/cpp)")
    parser.add_argument("--max-pages", dest="max_pages", type=int, default=0, help="Maximum pages to fetch (0 = unlimited)")
    parser.add_argument("--delay", dest="delay", type=float, default=0.01, help="Delay between requests in seconds")
    parser.add_argument("--timeout", dest="timeout", type=float, default=15.0, help="Per-request timeout in seconds")
    parser.add_argument("--user-agent", dest="ua", default="fuzzillai-devdocs-cpp-crawler/1.0", help="User-Agent header")

    args = parser.parse_args()
    out_dir = Path(args.out)
    
    start_urls = [
        args.start_url,
        "https://devdocs.io/cpp/algorithm/all_any_none_of",
        "https://devdocs.io/cpp/header",
        "https://devdocs.io/cpp/language",
        "https://devdocs.io/cpp/concept",
    ]

    for start_url in start_urls:
        crawl(
            start_url=start_url,
            out_dir=out_dir,
            max_pages=args.max_pages,
            delay_s=args.delay,
            user_agent=args.ua,
            timeout_s=args.timeout,
        )


if __name__ == "__main__":
    main()

