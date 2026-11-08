"""identity-passwd: change the current user's password through passwd(1).

Used by the Quickshell Identity Manager (IdentityService.qml). Reads exactly
two lines from stdin, the current and the new password, and prints exactly
one result line on stdout:

    OK
    BAD_CURRENT
    REJECTED <message from passwd/PAM>
    ERROR <message>

passwd runs on a pseudo-terminal, as GNOME's run-passwd does: PAM's text
conversation discards typed-ahead input when it switches echo off, and reads a
whole pipe buffer as one answer, so each answer is written only after its
prompt appears. Passwords never go into argv, the environment or any output;
the messages that are printed are scrubbed of them anyway.

IDENTITY_PASSWD_BIN overrides the passwd binary (tests only).
"""

import os
import pty
import re
import select
import signal
import sys
import time

TIMEOUT_S = 30.0

CURRENT_RE = re.compile(r"(current|old)[^:\n]*password[^:\n]*:\s*$", re.I)
RETYPE_RE = re.compile(r"(retype|re-enter|repeat|confirm)[^:\n]*password[^:\n]*:\s*$", re.I)
NEW_RE = re.compile(r"new[^:\n]*password[^:\n]*:\s*$", re.I)
BAD_CURRENT_RE = re.compile(r"authentication (token manipulation error|failure)", re.I)
NOISE_RE = re.compile(r"^(changing password for|passwd: password unchanged|passwd: authentication token manipulation error)", re.I)


def scrub(text, secrets):
    for s in secrets:
        if s:
            text = text.replace(s, "***")
    return text


def last_message(transcript, secrets):
    """The most useful human-readable line passwd printed, prompts excluded."""
    def informative(ln):
        if not ln or NOISE_RE.match(ln):
            return False
        return not (CURRENT_RE.search(ln) or RETYPE_RE.search(ln) or NEW_RE.search(ln))

    lines = [ln.strip() for ln in transcript.replace("\r", "\n").split("\n")]
    keep = [ln for ln in lines if informative(ln)]
    msg = keep[-1] if keep else ""
    msg = re.sub(r"^passwd:\s*", "", msg)
    return scrub(msg, secrets)[:200]


def classify(transcript, exit_code, prompts, secrets):
    """Map what passwd did to one result line."""
    if exit_code == 0 and "rejected" not in prompts:
        return "OK"
    if "rejected" in prompts:
        return "REJECTED " + (last_message(transcript, secrets) or "password rejected")
    if "new" not in prompts and BAD_CURRENT_RE.search(transcript):
        return "BAD_CURRENT"
    if "new" in prompts:
        return "REJECTED " + (last_message(transcript, secrets) or "password rejected")
    return "ERROR " + (last_message(transcript, secrets) or "passwd exited with code %d" % exit_code)


def read_input():
    data = sys.stdin.read()
    parts = data.split("\n")
    if len(parts) < 2:
        return None, None
    return parts[0], parts[1]


def run(current, new):
    binary = os.environ.get("IDENTITY_PASSWD_BIN", "passwd")
    env = dict(os.environ, LC_ALL="C", LANG="C", LANGUAGE="C")
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvpe(binary, [binary], env)
        finally:
            os._exit(127)

    transcript = ""
    pending = ""          # output since the last answer, searched for prompts
    prompts = []          # "current", "new", "retype", "rejected" in order seen
    deadline = time.monotonic() + TIMEOUT_S
    exit_code = None

    def answer(text):
        os.write(fd, (text + "\n").encode())

    while True:
        left = deadline - time.monotonic()
        if left <= 0:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
            return "ERROR timed out waiting for passwd"
        ready, _, _ = select.select([fd], [], [], min(left, 0.5))
        if ready:
            try:
                chunk = os.read(fd, 4096).decode(errors="replace")
            except OSError:
                chunk = ""
            if chunk == "":
                break
            transcript += chunk
            pending += chunk
            tail = pending.rstrip(" ")
            if RETYPE_RE.search(tail):
                prompts.append("retype")
                answer(new)
                pending = ""
            elif NEW_RE.search(tail):
                if "new" in prompts:
                    # Asked again: the previous new password was refused.
                    prompts.append("rejected")
                    os.kill(pid, signal.SIGTERM)
                    break
                prompts.append("new")
                answer(new)
                pending = ""
            elif CURRENT_RE.search(tail):
                if "current" in prompts:
                    prompts.append("rejected")
                    os.kill(pid, signal.SIGTERM)
                    break
                prompts.append("current")
                answer(current)
                pending = ""
        else:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                exit_code = os.waitstatus_to_exitcode(status)
                break

    if exit_code is None:
        _, status = os.waitpid(pid, 0)
        exit_code = os.waitstatus_to_exitcode(status)
    os.close(fd)
    if exit_code == 127 and not prompts:
        return "ERROR passwd not found"
    return classify(transcript, exit_code, prompts, (current, new))


def main():
    current, new = read_input()
    if current is None or new == "":
        print("ERROR expected the current and the new password on stdin")
        return 2
    result = run(current, new)
    print(result)
    return 0 if result == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
