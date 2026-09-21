import re

with open('lib/providers/app_state.dart', 'r') as f:
    content = f.read()

# Add imports
if 'import \'dart:isolate\';' not in content:
    content = content.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'dart:isolate';\nimport 'dart:ui';\nimport '../services/notification_service.dart';"
    )

# Fix transferredBytes -> bytesTransferred
content = content.replace("transfer.transferredBytes", "transfer.bytesTransferred")

with open('lib/providers/app_state.dart', 'w') as f:
    f.write(content)
