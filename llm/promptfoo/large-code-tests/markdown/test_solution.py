"""Behavioral tests for a markdown-to-HTML converter.
Solution must expose a function `to_html(markdown_text: str) -> str`."""
import pytest
import re
from solution import to_html


def _strip(s):
    """Normalize whitespace for comparison."""
    return re.sub(r'\s+', ' ', s).strip()


def test_h1():
    html = to_html("# Hello")
    assert "<h1>" in html and "Hello" in html and "</h1>" in html


def test_h2_h3():
    html = to_html("## Title\n### Sub")
    assert "<h2>" in html and "Title" in html
    assert "<h3>" in html and "Sub" in html


def test_paragraph():
    html = to_html("This is a paragraph.")
    assert "<p>" in html and "This is a paragraph." in html


def test_bold():
    html = to_html("**bold text**")
    # Could be <strong> or <b>
    assert ("<strong>" in html and "</strong>" in html) or ("<b>" in html and "</b>" in html)
    assert "bold text" in html


def test_italic():
    html = to_html("*italic*")
    assert ("<em>" in html and "</em>" in html) or ("<i>" in html and "</i>" in html)


def test_link():
    html = to_html("[Click](https://example.com)")
    assert '<a' in html and 'href="https://example.com"' in html and "Click" in html


def test_unordered_list():
    html = to_html("- one\n- two\n- three")
    assert "<ul>" in html and "</ul>" in html
    # All three items present as li
    assert html.count("<li>") >= 3


def test_fenced_code():
    md = "```\nprint('hi')\n```"
    html = to_html(md)
    assert "<code>" in html or "<pre>" in html
    assert "print" in html
