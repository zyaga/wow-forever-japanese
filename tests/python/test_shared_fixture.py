"""`conftest.shared`: a whole-store result is computed once per test run and read by every parallel worker."""

import conftest


def test_outside_a_parallel_run_the_value_is_computed_and_nothing_is_written(tmp_path, monkeypatch):
    monkeypatch.delenv("PYTEST_XDIST_WORKER", raising=False)
    calls = []
    assert conftest.shared(tmp_path, "store", lambda: calls.append(1) or {"a": 1}) == {"a": 1}
    assert calls == [1] and list(tmp_path.iterdir()) == []


def test_in_a_parallel_run_the_first_worker_computes_and_the_next_one_reads_it(tmp_path, monkeypatch):
    calls = []

    def produce():
        calls.append(1)
        return {"planned": ["x", "y"]}

    monkeypatch.setenv("PYTEST_XDIST_WORKER", "gw0")
    first = conftest.shared(tmp_path, "store", produce)
    monkeypatch.setenv("PYTEST_XDIST_WORKER", "gw1")
    second = conftest.shared(tmp_path, "store", produce)
    assert first == second == {"planned": ["x", "y"]}
    assert calls == [1]  # the second worker read the first one's result
    assert first is not second  # each worker has its own copy, as a session fixture gives it
