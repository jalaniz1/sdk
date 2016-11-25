// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:kernel/checks.dart';
import 'package:kernel/kernel.dart';

final String usage = '''
Usage: check_bench FILE.dill

Measures the time it takes to run sanity checks on the given program.
''';

main(List<String> args) {
  if (args.length != 1) {
    print(usage);
    exit(1);
  }
  var program = loadProgramFromBinary(args[0]);
  var watch = new Stopwatch()..start();
  runSanityChecks(program);
  print('Cold: ${watch.elapsedMilliseconds} ms');
  const int warmUpTrials = 20;
  for (int i = 0; i < warmUpTrials; ++i) {
    runSanityChecks(program);
  }
  watch.reset();
  const int numberOfTrials = 100;
  for (int i = 0; i < numberOfTrials; ++i) {
    runSanityChecks(program);
  }
  double millisecondsPerRun = watch.elapsedMilliseconds / numberOfTrials;
  print('Hot:  $millisecondsPerRun ms');
}
