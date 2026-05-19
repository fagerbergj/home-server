"""Behavioral tests for a Trie implementation.
Solution must expose a class `Trie` with methods: insert(word), search(word),
starts_with(prefix), delete(word). Returns bool for search/starts_with/delete."""
import pytest
from solution import Trie


def test_insert_search_basic():
    t = Trie()
    t.insert("hello")
    assert t.search("hello") is True
    assert t.search("hell") is False
    assert t.search("helloo") is False


def test_starts_with():
    t = Trie()
    t.insert("hello")
    t.insert("help")
    assert t.starts_with("hel") is True
    assert t.starts_with("hello") is True
    assert t.starts_with("help") is True
    assert t.starts_with("helping") is False


def test_empty_trie():
    t = Trie()
    assert t.search("anything") is False
    assert t.starts_with("a") is False


def test_multiple_words():
    t = Trie()
    words = ["apple", "app", "application", "apply", "banana"]
    for w in words:
        t.insert(w)
    for w in words:
        assert t.search(w) is True, f"missing: {w}"
    assert t.starts_with("appl") is True
    assert t.search("appl") is False  # prefix, not a full word


def test_delete_existing():
    t = Trie()
    t.insert("hello")
    t.insert("help")
    assert t.delete("hello") is True
    assert t.search("hello") is False
    # "help" should still be there
    assert t.search("help") is True


def test_delete_nonexistent():
    t = Trie()
    t.insert("hello")
    assert t.delete("world") is False
    assert t.search("hello") is True


def test_delete_does_not_break_prefix_words():
    t = Trie()
    t.insert("car")
    t.insert("card")
    t.delete("card")
    assert t.search("car") is True
    assert t.starts_with("car") is True
    assert t.search("card") is False
