import os
import shutil
import subprocess

KNOWN_PROTO_FILES = [
    "program.proto",
    "operations.proto",
    "sync.proto",
    "ast.proto"
]

def check_git_clean():
    """Check that the git repository does not have any uncommitted changes."""
    result = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], capture_output=True, check=True)
    assert result.stdout.decode().strip() == "", f"Unexpected modified files: {result.stdout.decode()}"

def check_proto():
    """Check that program.proto is up-to-date."""
    print("Checking generated protobuf files...")
    proto_dir = "Sources/Fuzzilli/Protobuf"
    subprocess.run(["python3", "./gen_programproto.py"], cwd=proto_dir, check=True)
    # gen_programproto.py should be a no-op.
    check_git_clean()

    if not shutil.which("protoc"):
        print("Skipping protobuf validation as protoc is not available.")
        return

    swift_protobuf_path = os.getcwd() + "/.build/checkouts/swift-protobuf"
    assert os.path.exists(swift_protobuf_path), \
        "The presubmit requires a swift-protobuf checkout, e.g. via \"swift build\""
    # Build swift-protobuf (for simplicity reuse the fetched repository from the swift-protobuf library).
    # Use a debug build as running it is very quick while building it with reelase might be slow.
    subprocess.run(["swift", "build", "-c", "debug"], cwd=swift_protobuf_path, check=True)
    env = os.environ.copy()
    env["PATH"] = f"{swift_protobuf_path}/.build/debug:" + env["PATH"]
    cmd = ["protoc", "--swift_opt=Visibility=Public", "--swift_out=."] + KNOWN_PROTO_FILES
    subprocess.run(cmd, cwd=proto_dir, check=True, env=env)
    # Regenerating the protobuf files should be a no-op.
    check_git_clean()

def main():
    check_git_clean()
    check_proto()
    # TODO(mliedtke): Ensure formatting delta is zero once we enable automated formatting.


if __name__ == '__main__':
  main()
