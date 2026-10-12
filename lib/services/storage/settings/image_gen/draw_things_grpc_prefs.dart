// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import '../settings_base.dart';

/// Draw Things gRPC connection and sampling knobs.
mixin DrawThingsGrpcPrefs on SettingsBase {
  String _drawThingsGrpcHost = '127.0.0.1';
  int _drawThingsGrpcPort = 7859;
  int _drawThingsSampler = 16;
  double _drawThingsShift = 3.0;
  int _drawThingsSeedMode = 2;
  bool _drawThingsTeaCache = false;
  bool _drawThingsCfgZeroStar = false;

  String get drawThingsGrpcHost => _drawThingsGrpcHost;
  int get drawThingsGrpcPort => _drawThingsGrpcPort;
  int get drawThingsSampler => _drawThingsSampler;
  double get drawThingsShift => _drawThingsShift;
  int get drawThingsSeedMode => _drawThingsSeedMode;
  bool get drawThingsTeaCache => _drawThingsTeaCache;
  bool get drawThingsCfgZeroStar => _drawThingsCfgZeroStar;

  void loadDrawThingsGrpcPrefs() {
    _drawThingsGrpcHost =
        prefs?.getString(k('draw_things_grpc_host')) ?? '127.0.0.1';
    _drawThingsGrpcPort = prefs?.getInt(k('draw_things_grpc_port')) ?? 7859;
    _drawThingsSampler = prefs?.getInt(k('draw_things_sampler')) ?? 16;
    _drawThingsShift = prefs?.getDouble(k('draw_things_shift')) ?? 3.0;
    _drawThingsSeedMode = prefs?.getInt(k('draw_things_seed_mode')) ?? 2;
    _drawThingsTeaCache = prefs?.getBool(k('draw_things_tea_cache')) ?? false;
    _drawThingsCfgZeroStar =
        prefs?.getBool(k('draw_things_cfg_zero_star')) ?? false;
  }

  Future<void> setDrawThingsGrpcHost(String value) async {
    _drawThingsGrpcHost = value.trim();
    await prefs?.setString(k('draw_things_grpc_host'), _drawThingsGrpcHost);
    notify();
  }

  Future<void> setDrawThingsGrpcPort(int value) async {
    _drawThingsGrpcPort = value;
    await prefs?.setInt(k('draw_things_grpc_port'), value);
    notify();
  }

  Future<void> setDrawThingsSampler(int value) async {
    _drawThingsSampler = value;
    await prefs?.setInt(k('draw_things_sampler'), value);
    notify();
  }

  Future<void> setDrawThingsShift(double value) async {
    _drawThingsShift = value;
    await prefs?.setDouble(k('draw_things_shift'), value);
    notify();
  }

  Future<void> setDrawThingsSeedMode(int value) async {
    _drawThingsSeedMode = value;
    await prefs?.setInt(k('draw_things_seed_mode'), value);
    notify();
  }

  Future<void> setDrawThingsTeaCache(bool value) async {
    _drawThingsTeaCache = value;
    await prefs?.setBool(k('draw_things_tea_cache'), value);
    notify();
  }

  Future<void> setDrawThingsCfgZeroStar(bool value) async {
    _drawThingsCfgZeroStar = value;
    await prefs?.setBool(k('draw_things_cfg_zero_star'), value);
    notify();
  }
}
