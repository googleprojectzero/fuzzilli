#!/usr/bin/env python3

from pathlib import Path
from html.parser import HTMLParser
from html import unescape
import re


class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text_parts = []
        self.skip_tags = {'script', 'style', 'noscript', 'meta', 'link', 'svg', 'path'}
        self.skip = False
        
    def handle_starttag(self, tag: str, attrs):
        self.skip = tag.lower() in self.skip_tags
        
    def handle_endtag(self, tag: str):
        self.skip = False
        
    def handle_data(self, data: str):
        if not self.skip and data.strip():
            self.text_parts.append(data.strip())
    
    def get_text(self) -> str:
        text = ' '.join(self.text_parts)
        text = unescape(text)
        text = re.sub(r'\s+', ' ', text)
        text = re.sub(r' +', ' ', text)
        return text.strip()


def extract_text_from_html(html_path: Path) -> str:
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        parser = TextExtractor()
        parser.feed(content)
        return parser.get_text()
    except Exception as e:
        return f"Error extracting text: {e}"


def convert_html_to_txt(root_dir: Path):
    root_dir = Path(root_dir)
    
    for html_file in root_dir.rglob('*.html'):
        txt_file = html_file.with_suffix('.txt')
        
        print(f"Converting: {html_file.relative_to(root_dir)}")
        
        text_content = extract_text_from_html(html_file)
        
        try:
            txt_file.write_text(text_content, encoding='utf-8')
            print(f"  -> {txt_file.relative_to(root_dir)}")
        except Exception as e:
            print(f"  Error writing {txt_file}: {e}")
    
    print("\nConversion complete!")


def main():
    import sys
    
    if len(sys.argv) > 1:
        root_dir = Path(sys.argv[1])
    else:
        root_dir = Path(__file__).parent
    
    convert_html_to_txt(root_dir)


if __name__ == "__main__":
    main()

