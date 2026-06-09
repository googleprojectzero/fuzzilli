# Copyright 2026 Google LLC
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import sys
# depot_tools runs presubmit scripts in an isolated environment where the
# repository root is not in sys.path. We must explicitly add it to import local
# packages.
sys.path.insert(0, '.')

from Tools import presubmit

def CheckChangeOnUpload(input_api, output_api):
    results = []
    try:
        presubmit.check_all()
    except Exception as e:
        results.append(output_api.PresubmitError(str(e)))
    return results
