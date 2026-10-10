// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/widgets/porch_snack_bar.dart';

/// "`name` created successfully!" after either character creator finishes.
SnackBar characterCreatedSnackBar(BuildContext context, String name) =>
    porchSnackBar(context, '$name created successfully!');
