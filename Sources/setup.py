# import Agentic_System.rises_the_fog as fog
import subprocess
import os

# fog.run()

def revert_to_original():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    a = os.path.join(script_dir, "Agentic_System/orginals/ProgramTemplateWeights.swift")
    b = os.path.join(script_dir, "Fuzzilli/CodeGen/ProgramTemplateWeights.swift")
    os.rename(a, b)
    a = os.path.join(script_dir, "Agentic_System/orginals/ProgramTemplates.swift")
    b = os.path.join(script_dir, "Fuzzilli/CodeGen/ProgramTemplates.swift")
    os.rename(a, b)


def write_sql(reuslt: bool):
    if reuslt:
        with open("sql.sql", "r") as f:
            sql = f.read()
    else:
        with open("sql.sql", "r") as f:
            sql = f.read()

    return sql

result = subprocess.run(["swift", "build"], capture_output=True, text=True)
if result.returncode == 0:
    write_sql(True)
    print("Build templates succeeded")
else:
    write_sql(False)
    revert_to_original()
    print("Build templates failed")
    print(result.stdout)
    print(result.stderr)
    r2 = subprocess.run(["swift", "build"], capture_output=True, text=True)
    if r2.returncode == 0:
        print("Build reverted succeeded")
    else:
        print("safety revert failed")
        print(r2.stdout)
        print(r2.stderr)
        exit(1)

