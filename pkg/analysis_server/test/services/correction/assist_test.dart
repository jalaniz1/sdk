// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/plugin/edit/assist/assist_core.dart';
import 'package:analysis_server/plugin/edit/assist/assist_dart.dart';
import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/correction/assist_internal.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/standard_resolution_map.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:plugin/manager.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../abstract_single_unit.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AssistProcessorTest);
    defineReflectiveTests(AssistProcessorTest_UseCFE);
  });
}

@reflectiveTest
class AssistProcessorTest extends AbstractSingleUnitTest {
  int offset;
  int length;

  Assist assist;
  SourceChange change;
  String resultCode;
  LinkedEditGroup linkedPositionGroup;

  bool get omitNew => true;

  /**
   * Asserts that there is an [Assist] of the given [kind] at [offset] which
   * produces the [expected] code when applied to [testCode].
   */
  assertHasAssist(AssistKind kind, String expected) async {
    assist = await _assertHasAssist(kind);
    change = assist.change;
    expect(change.id, kind.id);
    // apply to "file"
    List<SourceFileEdit> fileEdits = change.edits;
    expect(fileEdits, hasLength(1));
    resultCode = SourceEdit.applySequence(testCode, change.edits[0].edits);
    // verify
    expect(resultCode, expected);
  }

  /**
   * Calls [assertHasAssist] at the offset of [offsetSearch] in [testCode].
   */
  assertHasAssistAt(
      String offsetSearch, AssistKind kind, String expected) async {
    offset = findOffset(offsetSearch);
    await assertHasAssist(kind, expected);
  }

  /**
   * Asserts that there is no [Assist] of the given [kind] at [offset].
   */
  assertNoAssist(AssistKind kind) async {
    List<Assist> assists = await _computeAssists();
    for (Assist assist in assists) {
      if (assist.kind == kind) {
        fail('Unexpected assist $kind in\n${assists.join('\n')}');
      }
    }
  }

  /**
   * Calls [assertNoAssist] at the offset of [offsetSearch] in [testCode].
   */
  assertNoAssistAt(String offsetSearch, AssistKind kind) async {
    offset = findOffset(offsetSearch);
    await assertNoAssist(kind);
  }

  List<LinkedEditSuggestion> expectedSuggestions(
      LinkedEditSuggestionKind kind, List<String> values) {
    return values.map((value) {
      return new LinkedEditSuggestion(value, kind);
    }).toList();
  }

  void processRequiredPlugins() {
    ExtensionManager manager = new ExtensionManager();
    manager.processPlugins(AnalysisEngine.instance.requiredPlugins);
  }

  void setUp() {
    super.setUp();
    offset = 0;
    length = 0;
  }

  test_addTypeAnnotation_BAD_privateType_closureParameter() async {
    addSource('/project/my_lib.dart', '''
library my_lib;
class A {}
class _B extends A {}
foo(f(_B p)) {}
''');
    await resolveTestUnit('''
import 'my_lib.dart';
main() {
  foo((test) {});
}
 ''');
    await assertNoAssistAt('test)', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_BAD_privateType_declaredIdentifier() async {
    addSource('/project/my_lib.dart', '''
library my_lib;
class A {}
class _B extends A {}
List<_B> getValues() => [];
''');
    await resolveTestUnit('''
import 'my_lib.dart';
class A<T> {
  main() {
    for (var item in getValues()) {
    }
  }
}
''');
    await assertNoAssistAt('var item', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_BAD_privateType_list() async {
    // This is now failing because we're suggesting "List" rather than nothing.
    // Is it really better to produce nothing?
    addSource('/project/my_lib.dart', '''
library my_lib;
class A {}
class _B extends A {}
List<_B> getValues() => [];
''');
    await resolveTestUnit('''
import 'my_lib.dart';
main() {
  var v = getValues();
}
''');
    await assertHasAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
import 'my_lib.dart';
main() {
  List v = getValues();
}
''');
  }

  test_addTypeAnnotation_BAD_privateType_variable() async {
    addSource('/project/my_lib.dart', '''
library my_lib;
class A {}
class _B extends A {}
_B getValue() => new _B();
''');
    await resolveTestUnit('''
import 'my_lib.dart';
main() {
  var v = getValue();
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_classField_OK_final() async {
    await resolveTestUnit('''
class A {
  final f = 0;
}
''');
    await assertHasAssistAt('final ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class A {
  final int f = 0;
}
''');
  }

  test_addTypeAnnotation_classField_OK_int() async {
    await resolveTestUnit('''
class A {
  var f = 0;
}
''');
    await await assertHasAssistAt(
        'var ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class A {
  int f = 0;
}
''');
  }

  test_addTypeAnnotation_declaredIdentifier_BAD_hasTypeAnnotation() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
  }
}
''');
    await assertNoAssistAt('item in', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_declaredIdentifier_BAD_inForEachBody() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (var item in items) {
    42;
  }
}
''');
    await assertNoAssistAt('42;', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_declaredIdentifier_BAD_unknownType() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main() {
  for (var item in unknownList) {
  }
}
''');
    await assertNoAssistAt('item in', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_declaredIdentifier_generic_OK() async {
    await resolveTestUnit('''
class A<T> {
  main(List<List<T>> items) {
    for (var item in items) {
    }
  }
}
''');
    await assertHasAssistAt('item in', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class A<T> {
  main(List<List<T>> items) {
    for (List<T> item in items) {
    }
  }
}
''');
  }

  test_addTypeAnnotation_declaredIdentifier_OK() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (var item in items) {
  }
}
''');
    // on identifier
    await assertHasAssistAt('item in', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main(List<String> items) {
  for (String item in items) {
  }
}
''');
    // on "for"
    await assertHasAssistAt('for (', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main(List<String> items) {
  for (String item in items) {
  }
}
''');
  }

  test_addTypeAnnotation_declaredIdentifier_OK_addImport_dartUri() async {
    addSource('/project/my_lib.dart', r'''
import 'dart:async';
List<Future<int>> getFutures() => null;
''');
    await resolveTestUnit('''
import 'my_lib.dart';
main() {
  for (var future in getFutures()) {
  }
}
''');
    await assertHasAssistAt('future in', DartAssistKind.ADD_TYPE_ANNOTATION, '''
import 'dart:async';

import 'my_lib.dart';
main() {
  for (Future<int> future in getFutures()) {
  }
}
''');
  }

  test_addTypeAnnotation_declaredIdentifier_OK_final() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (final item in items) {
  }
}
''');
    await assertHasAssistAt('item in', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main(List<String> items) {
  for (final String item in items) {
  }
}
''');
  }

  test_addTypeAnnotation_local_BAD_bottom() async {
    await resolveTestUnit('''
main() {
  var v = throw 42;
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_hasTypeAnnotation() async {
    await resolveTestUnit('''
main() {
  int v = 42;
}
''');
    await assertNoAssistAt(' = 42', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_multiple() async {
    await resolveTestUnit('''
main() {
  var a = 1, b = '';
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_noValue() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main() {
  var v;
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_null() async {
    await resolveTestUnit('''
main() {
  var v = null;
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_onInitializer() async {
    await resolveTestUnit('''
main() {
  var abc = 0;
}
''');
    await assertNoAssistAt('0;', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_BAD_unknown() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main() {
  var v = unknownVar;
}
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_local_generic_OK_literal() async {
    await resolveTestUnit('''
class A {
  main(List<int> items) {
    var v = items;
  }
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class A {
  main(List<int> items) {
    List<int> v = items;
  }
}
''');
  }

  test_addTypeAnnotation_local_generic_OK_local() async {
    await resolveTestUnit('''
class A<T> {
  main(List<T> items) {
    var v = items;
  }
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class A<T> {
  main(List<T> items) {
    List<T> v = items;
  }
}
''');
  }

  test_addTypeAnnotation_local_OK_addImport_dartUri() async {
    addSource('/project/my_lib.dart', r'''
import 'dart:async';
Future<int> getFutureInt() => null;
''');
    await resolveTestUnit('''
import 'my_lib.dart';
main() {
  var v = getFutureInt();
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
import 'dart:async';

import 'my_lib.dart';
main() {
  Future<int> v = getFutureInt();
}
''');
  }

  test_addTypeAnnotation_local_OK_addImport_notLibraryUnit() async {
    // prepare library
    addSource('/project/my_lib.dart', r'''
import 'dart:async';
Future<int> getFutureInt() => null;
''');
    // prepare code
    String appCode = r'''
library my_app;
import 'my_lib.dart';
part 'test.dart';
''';
    testCode = r'''
part of my_app;
main() {
  var v = getFutureInt();
}
''';
    // add sources
    addSource('/project/app.dart', appCode);
    testSource = addSource('/project/test.dart', testCode);
    // resolve
    await resolveTestUnit(testCode);
    // prepare the assist
    offset = findOffset('v = ');
    assist = await _assertHasAssist(DartAssistKind.ADD_TYPE_ANNOTATION);
    change = assist.change;
    // verify
    {
      var testFileEdit = change.getFileEdit(convertPath('/project/app.dart'));
      var resultCode = SourceEdit.applySequence(appCode, testFileEdit.edits);
      expect(resultCode, '''
library my_app;
import 'dart:async';

import 'my_lib.dart';
part 'test.dart';
''');
    }
    {
      var testFileEdit = change.getFileEdit(convertPath('/project/test.dart'));
      var resultCode = SourceEdit.applySequence(testCode, testFileEdit.edits);
      expect(resultCode, '''
part of my_app;
main() {
  Future<int> v = getFutureInt();
}
''');
    }
  }

  test_addTypeAnnotation_local_OK_addImport_relUri() async {
    addSource('/project/aa/bbb/lib_a.dart', r'''
class MyClass {}
''');
    addSource('/project/ccc/lib_b.dart', r'''
import '../aa/bbb/lib_a.dart';
MyClass newMyClass() => null;
''');
    await resolveTestUnit('''
import 'ccc/lib_b.dart';
main() {
  var v = newMyClass();
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
import 'aa/bbb/lib_a.dart';
import 'ccc/lib_b.dart';
main() {
  MyClass v = newMyClass();
}
''');
  }

  test_addTypeAnnotation_local_OK_Function() async {
    await resolveTestUnit('''
main() {
  var v = () => 1;
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main() {
  int Function() v = () => 1;
}
''');
  }

  test_addTypeAnnotation_local_OK_int() async {
    await resolveTestUnit('''
main() {
  var v = 0;
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main() {
  int v = 0;
}
''');
  }

  test_addTypeAnnotation_local_OK_List() async {
    await resolveTestUnit('''
main() {
  var v = <String>[];
}
''');
    await assertHasAssistAt('v =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main() {
  List<String> v = <String>[];
}
''');
  }

  test_addTypeAnnotation_local_OK_localType() async {
    await resolveTestUnit('''
class C {}
C f() => null;
main() {
  var x = f();
}
''');
    await assertHasAssistAt('x =', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class C {}
C f() => null;
main() {
  C x = f();
}
''');
  }

  test_addTypeAnnotation_local_OK_onName() async {
    await resolveTestUnit('''
main() {
  var abc = 0;
}
''');
    await assertHasAssistAt('bc', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main() {
  int abc = 0;
}
''');
  }

  test_addTypeAnnotation_local_OK_onVar() async {
    await resolveTestUnit('''
main() {
  var v = 0;
}
''');
    await assertHasAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
main() {
  int v = 0;
}
''');
  }

  test_addTypeAnnotation_OK_privateType_sameLibrary() async {
    await resolveTestUnit('''
class _A {}
_A getValue() => new _A();
main() {
  var v = getValue();
}
''');
    await assertHasAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
class _A {}
_A getValue() => new _A();
main() {
  _A v = getValue();
}
''');
  }

  test_addTypeAnnotation_parameter_BAD_hasExplicitType() async {
    await resolveTestUnit('''
foo(f(int p)) {}
main() {
  foo((num test) {});
}
''');
    await assertNoAssistAt('test', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_parameter_BAD_noPropagatedType() async {
    await resolveTestUnit('''
foo(f(p)) {}
main() {
  foo((test) {});
}
''');
    await assertNoAssistAt('test', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_parameter_OK() async {
    await resolveTestUnit('''
foo(f(int p)) {}
main() {
  foo((test) {});
}
''');
    await assertHasAssistAt('test', DartAssistKind.ADD_TYPE_ANNOTATION, '''
foo(f(int p)) {}
main() {
  foo((int test) {});
}
''');
  }

  test_addTypeAnnotation_topLevelField_BAD_multiple() async {
    await resolveTestUnit('''
var A = 1, V = '';
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_topLevelField_BAD_noValue() async {
    await resolveTestUnit('''
var V;
''');
    await assertNoAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION);
  }

  test_addTypeAnnotation_topLevelField_OK_int() async {
    await resolveTestUnit('''
var V = 0;
''');
    await assertHasAssistAt('var ', DartAssistKind.ADD_TYPE_ANNOTATION, '''
int V = 0;
''');
  }

  test_assignToLocalVariable() async {
    await resolveTestUnit('''
main() {
  List<int> bytes;
  readBytes();
}
List<int> readBytes() => <int>[];
''');
    await assertHasAssistAt(
        'readBytes();', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE, '''
main() {
  List<int> bytes;
  var readBytes = readBytes();
}
List<int> readBytes() => <int>[];
''');
    _assertLinkedGroup(
        change.linkedEditGroups[0],
        ['readBytes = '],
        expectedSuggestions(LinkedEditSuggestionKind.VARIABLE,
            ['list', 'bytes2', 'readBytes']));
  }

  test_assignToLocalVariable_alreadyAssignment() async {
    await resolveTestUnit('''
main() {
  var vvv;
  vvv = 42;
}
''');
    await assertNoAssistAt('vvv =', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE);
  }

  test_assignToLocalVariable_inClosure() async {
    await resolveTestUnit(r'''
main() {
  print(() {
    12345;
  });
}
''');
    await assertHasAssistAt('345', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE, '''
main() {
  print(() {
    var i = 12345;
  });
}
''');
  }

  test_assignToLocalVariable_invocationArgument() async {
    await resolveTestUnit(r'''
main() {
  f(12345);
}
void f(p) {}
''');
    await assertNoAssistAt('345', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE);
  }

  test_assignToLocalVariable_throw() async {
    await resolveTestUnit('''
main() {
  throw 42;
}
''');
    await assertNoAssistAt('throw ', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE);
  }

  test_assignToLocalVariable_void() async {
    await resolveTestUnit('''
main() {
  f();
}
void f() {}
''');
    await assertNoAssistAt('f();', DartAssistKind.ASSIGN_TO_LOCAL_VARIABLE);
  }

  test_convertDocumentationIntoBlock_BAD_alreadyBlock() async {
    await resolveTestUnit('''
/**
 * AAAAAAA
 */
class A {}
''');
    await assertNoAssistAt(
        'AAA', DartAssistKind.CONVERT_DOCUMENTATION_INTO_BLOCK);
  }

  test_convertDocumentationIntoBlock_BAD_notDocumentation() async {
    await resolveTestUnit('''
// AAAA
class A {}
''');
    await assertNoAssistAt(
        'AAA', DartAssistKind.CONVERT_DOCUMENTATION_INTO_BLOCK);
  }

  test_convertDocumentationIntoBlock_OK_noSpaceBeforeText() async {
    await resolveTestUnit('''
class A {
  /// AAAAA
  ///BBBBB
  ///
  /// CCCCC
  mmm() {}
}
''');
    await assertHasAssistAt(
        'AAAAA', DartAssistKind.CONVERT_DOCUMENTATION_INTO_BLOCK, '''
class A {
  /**
   * AAAAA
   *BBBBB
   *
   * CCCCC
   */
  mmm() {}
}
''');
  }

  test_convertDocumentationIntoBlock_OK_onReference() async {
    await resolveTestUnit('''
/// AAAAAAA [int] AAAAAAA
class A {}
''');
    await assertHasAssistAt(
        'nt]', DartAssistKind.CONVERT_DOCUMENTATION_INTO_BLOCK, '''
/**
 * AAAAAAA [int] AAAAAAA
 */
class A {}
''');
  }

  test_convertDocumentationIntoBlock_OK_onText() async {
    await resolveTestUnit('''
class A {
  /// AAAAAAA [int] AAAAAAA
  /// BBBBBBBB BBBB BBBB
  /// CCC [A] CCCCCCCCCCC
  mmm() {}
}
''');
    await assertHasAssistAt(
        'AAA [', DartAssistKind.CONVERT_DOCUMENTATION_INTO_BLOCK, '''
class A {
  /**
   * AAAAAAA [int] AAAAAAA
   * BBBBBBBB BBBB BBBB
   * CCC [A] CCCCCCCCCCC
   */
  mmm() {}
}
''');
  }

  test_convertDocumentationIntoLine_BAD_alreadyLine() async {
    await resolveTestUnit('''
/// AAAAAAA
class A {}
''');
    await assertNoAssistAt(
        'AAA', DartAssistKind.CONVERT_DOCUMENTATION_INTO_LINE);
  }

  test_convertDocumentationIntoLine_BAD_notDocumentation() async {
    await resolveTestUnit('''
/* AAAA */
class A {}
''');
    await assertNoAssistAt(
        'AAA', DartAssistKind.CONVERT_DOCUMENTATION_INTO_LINE);
  }

  test_convertDocumentationIntoLine_OK_onReference() async {
    await resolveTestUnit('''
/**
 * AAAAAAA [int] AAAAAAA
 */
class A {}
''');
    await assertHasAssistAt(
        'nt]', DartAssistKind.CONVERT_DOCUMENTATION_INTO_LINE, '''
/// AAAAAAA [int] AAAAAAA
class A {}
''');
  }

  test_convertDocumentationIntoLine_OK_onText() async {
    await resolveTestUnit('''
class A {
  /**
   * AAAAAAA [int] AAAAAAA
   * BBBBBBBB BBBB BBBB
   * CCC [A] CCCCCCCCCCC
   */
  mmm() {}
}
''');
    await assertHasAssistAt(
        'AAA [', DartAssistKind.CONVERT_DOCUMENTATION_INTO_LINE, '''
class A {
  /// AAAAAAA [int] AAAAAAA
  /// BBBBBBBB BBBB BBBB
  /// CCC [A] CCCCCCCCCCC
  mmm() {}
}
''');
  }

  test_convertDocumentationIntoLine_OK_onText_hasFirstLine() async {
    await resolveTestUnit('''
class A {
  /** AAAAAAA [int] AAAAAAA
   * BBBBBBBB BBBB BBBB
   * CCC [A] CCCCCCCCCCC
   */
  mmm() {}
}
''');
    await assertHasAssistAt(
        'AAA [', DartAssistKind.CONVERT_DOCUMENTATION_INTO_LINE, '''
class A {
  /// AAAAAAA [int] AAAAAAA
  /// BBBBBBBB BBBB BBBB
  /// CCC [A] CCCCCCCCCCC
  mmm() {}
}
''');
  }

  test_convertPartOfToUri_file_nonSibling() async {
    addSource('/pkg/lib/foo.dart', '''
library foo;
part 'src/bar.dart';
''');
    testFile = resourceProvider.convertPath('/pkg/lib/src/bar.dart');
    await resolveTestUnit('''
part of foo;
''');
    await assertHasAssistAt('foo', DartAssistKind.CONVERT_PART_OF_TO_URI, '''
part of '../foo.dart';
''');
  }

  test_convertPartOfToUri_file_sibling() async {
    addSource('/pkg/foo.dart', '''
library foo;
part 'bar.dart';
''');
    testFile = resourceProvider.convertPath('/pkg/bar.dart');
    await resolveTestUnit('''
part of foo;
''');
    await assertHasAssistAt('foo', DartAssistKind.CONVERT_PART_OF_TO_URI, '''
part of 'foo.dart';
''');
  }

  test_convertToAsyncBody_BAD_async() async {
    await resolveTestUnit('''
import 'dart:async';
Future<String> f() async => '';
''');
    await assertNoAssistAt('=>', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_BAD_asyncStar() async {
    await resolveTestUnit('''
import 'dart:async';
Stream<String> f() async* {}
''');
    await assertNoAssistAt('{}', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_BAD_constructor() async {
    await resolveTestUnit('''
class C {
  C() {}
}
''');
    await assertNoAssistAt('{}', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_BAD_inBody_block() async {
    await resolveTestUnit('''
class C {
  void foo() {
    print(42);
  }
}
''');
    await assertNoAssistAt('print', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_BAD_inBody_expression() async {
    await resolveTestUnit('''
class C {
  void foo() => print(42);
}
''');
    await assertNoAssistAt('print', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_BAD_syncStar() async {
    await resolveTestUnit('''
Iterable<String> f() sync* {}
''');
    await assertNoAssistAt('{}', DartAssistKind.CONVERT_INTO_ASYNC_BODY);
  }

  test_convertToAsyncBody_OK_closure() async {
    await resolveTestUnit('''
main() {
  f(() => 123);
}
f(g) {}
''');
    await assertHasAssistAt('=>', DartAssistKind.CONVERT_INTO_ASYNC_BODY, '''
main() {
  f(() async => 123);
}
f(g) {}
''');
  }

  test_convertToAsyncBody_OK_function() async {
    // TODO(brianwilkerson) Remove the "class C {}" when the bug in the builder
    // is fixed that causes the import to be incorrectly inserted when the first
    // character in the file is also being modified.
    await resolveTestUnit('''
class C {}
String f() => '';
''');
    await assertHasAssistAt('=>', DartAssistKind.CONVERT_INTO_ASYNC_BODY, '''
import 'dart:async';

class C {}
Future<String> f() async => '';
''');
  }

  test_convertToAsyncBody_OK_method() async {
    await resolveTestUnit('''
class C {
  int m() { return 0; }
}
''');
    await assertHasAssistAt(
        '{ return', DartAssistKind.CONVERT_INTO_ASYNC_BODY, '''
import 'dart:async';

class C {
  Future<int> m() async { return 0; }
}
''');
  }

  test_convertToAsyncBody_OK_method_noReturnType() async {
    await resolveTestUnit('''
class C {
  m() { return 0; }
}
''');
    await assertHasAssistAt(
        '{ return', DartAssistKind.CONVERT_INTO_ASYNC_BODY, '''
class C {
  m() async { return 0; }
}
''');
  }

  test_convertToBlockBody_BAD_inExpression() async {
    await resolveTestUnit('''
main() => 123;
''');
    await assertNoAssistAt('123;', DartAssistKind.CONVERT_INTO_BLOCK_BODY);
  }

  test_convertToBlockBody_BAD_noEnclosingFunction() async {
    await resolveTestUnit('''
var v = 123;
''');
    await assertNoAssistAt('v =', DartAssistKind.CONVERT_INTO_BLOCK_BODY);
  }

  test_convertToBlockBody_BAD_notExpressionBlock() async {
    await resolveTestUnit('''
fff() {
  return 123;
}
''');
    await assertNoAssistAt('fff() {', DartAssistKind.CONVERT_INTO_BLOCK_BODY);
  }

  test_convertToBlockBody_OK_async() async {
    await resolveTestUnit('''
class A {
  mmm() async => 123;
}
''');
    await assertHasAssistAt('mmm()', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
class A {
  mmm() async {
    return 123;
  }
}
''');
  }

  test_convertToBlockBody_OK_closure() async {
    await resolveTestUnit('''
setup(x) {}
main() {
  setup(() => 42);
}
''');
    await assertHasAssistAt(
        '() => 42', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
setup(x) {}
main() {
  setup(() {
    return 42;
  });
}
''');
    {
      Position exitPos = change.selection;
      expect(exitPos, isNotNull);
      expect(exitPos.file, testFile);
      expect(exitPos.offset - 3, resultCode.indexOf('42;'));
    }
  }

  test_convertToBlockBody_OK_closure_voidExpression() async {
    await resolveTestUnit('''
setup(x) {}
main() {
  setup(() => print('done'));
}
''');
    await assertHasAssistAt(
        '() => print', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
setup(x) {}
main() {
  setup(() {
    print('done');
  });
}
''');
    {
      Position exitPos = change.selection;
      expect(exitPos, isNotNull);
      expect(exitPos.file, testFile);
      expect(exitPos.offset - 3, resultCode.indexOf("');"));
    }
  }

  test_convertToBlockBody_OK_constructor() async {
    await resolveTestUnit('''
class A {
  factory A() => null;
}
''');
    await assertHasAssistAt('A()', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
class A {
  factory A() {
    return null;
  }
}
''');
  }

  test_convertToBlockBody_OK_method() async {
    await resolveTestUnit('''
class A {
  mmm() => 123;
}
''');
    await assertHasAssistAt('mmm()', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
class A {
  mmm() {
    return 123;
  }
}
''');
  }

  test_convertToBlockBody_OK_onArrow() async {
    await resolveTestUnit('''
fff() => 123;
''');
    await assertHasAssistAt('=>', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
fff() {
  return 123;
}
''');
  }

  test_convertToBlockBody_OK_onName() async {
    await resolveTestUnit('''
fff() => 123;
''');
    await assertHasAssistAt('fff()', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
fff() {
  return 123;
}
''');
  }

  test_convertToBlockBody_OK_throw() async {
    await resolveTestUnit('''
class A {
  mmm() => throw 'error';
}
''');
    await assertHasAssistAt('mmm()', DartAssistKind.CONVERT_INTO_BLOCK_BODY, '''
class A {
  mmm() {
    throw 'error';
  }
}
''');
  }

  test_convertToDoubleQuotedString_BAD_one_embeddedTarget() async {
    await resolveTestUnit('''
main() {
  print('a"b"c');
}
''');
    await assertNoAssistAt(
        "'a", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING);
  }

  test_convertToDoubleQuotedString_BAD_one_enclosingTarget() async {
    await resolveTestUnit('''
main() {
  print("abc");
}
''');
    await assertNoAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING);
  }

  test_convertToDoubleQuotedString_BAD_three_embeddedTarget() async {
    await resolveTestUnit("""
main() {
  print('''a""\"c''');
}
""");
    await assertNoAssistAt(
        "'a", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING);
  }

  test_convertToDoubleQuotedString_BAD_three_enclosingTarget() async {
    await resolveTestUnit('''
main() {
  print("""abc""");
}
''');
    await assertNoAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING);
  }

  test_convertToDoubleQuotedString_OK_one_interpolation() async {
    await resolveTestUnit(r'''
main() {
  var b = 'b';
  var c = 'c';
  print('a $b-${c} d');
}
''');
    await assertHasAssistAt(
        r"'a $b", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, r'''
main() {
  var b = 'b';
  var c = 'c';
  print("a $b-${c} d");
}
''');
  }

  test_convertToDoubleQuotedString_OK_one_raw() async {
    await resolveTestUnit('''
main() {
  print(r'abc');
}
''');
    await assertHasAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, '''
main() {
  print(r"abc");
}
''');
  }

  test_convertToDoubleQuotedString_OK_one_simple() async {
    await resolveTestUnit('''
main() {
  print('abc');
}
''');
    await assertHasAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, '''
main() {
  print("abc");
}
''');
  }

  test_convertToDoubleQuotedString_OK_three_interpolation() async {
    await resolveTestUnit(r"""
main() {
  var b = 'b';
  var c = 'c';
  print('''a $b-${c} d''');
}
""");
    await assertHasAssistAt(
        r"'a $b", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, r'''
main() {
  var b = 'b';
  var c = 'c';
  print("""a $b-${c} d""");
}
''');
  }

  test_convertToDoubleQuotedString_OK_three_raw() async {
    await resolveTestUnit("""
main() {
  print(r'''abc''');
}
""");
    await assertHasAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, '''
main() {
  print(r"""abc""");
}
''');
  }

  test_convertToDoubleQuotedString_OK_three_simple() async {
    await resolveTestUnit("""
main() {
  print('''abc''');
}
""");
    await assertHasAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_DOUBLE_QUOTED_STRING, '''
main() {
  print("""abc""");
}
''');
  }

  test_convertToExpressionBody_BAD_already() async {
    await resolveTestUnit('''
fff() => 42;
''');
    await assertNoAssistAt(
        'fff()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_BAD_inExpression() async {
    await resolveTestUnit('''
main() {
  return 42;
}
''');
    await assertNoAssistAt('42;', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_BAD_moreThanOneStatement() async {
    await resolveTestUnit('''
fff() {
  var v = 42;
  return v;
}
''');
    await assertNoAssistAt(
        'fff()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_BAD_noEnclosingFunction() async {
    await resolveTestUnit('''
var V = 42;
''');
    await assertNoAssistAt('V = ', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_BAD_noReturn() async {
    await resolveTestUnit('''
fff() {
  var v = 42;
}
''');
    await assertNoAssistAt(
        'fff()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_BAD_noReturnValue() async {
    await resolveTestUnit('''
fff() {
  return;
}
''');
    await assertNoAssistAt(
        'fff()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY);
  }

  test_convertToExpressionBody_OK_async() async {
    await resolveTestUnit('''
class A {
  mmm() async {
    return 42;
  }
}
''');
    await assertHasAssistAt(
        'mmm', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
class A {
  mmm() async => 42;
}
''');
  }

  test_convertToExpressionBody_OK_closure() async {
    await resolveTestUnit('''
setup(x) {}
main() {
  setup(() {
    return 42;
  });
}
''');
    await assertHasAssistAt(
        'return', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
setup(x) {}
main() {
  setup(() => 42);
}
''');
  }

  test_convertToExpressionBody_OK_closure_voidExpression() async {
    await resolveTestUnit('''
setup(x) {}
main() {
  setup((_) {
    print('test');
  });
}
''');
    await assertHasAssistAt(
        '(_) {', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
setup(x) {}
main() {
  setup((_) => print('test'));
}
''');
  }

  test_convertToExpressionBody_OK_constructor() async {
    await resolveTestUnit('''
class A {
  factory A() {
    return null;
  }
}
''');
    await assertHasAssistAt(
        'A()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
class A {
  factory A() => null;
}
''');
  }

  test_convertToExpressionBody_OK_function_onBlock() async {
    await resolveTestUnit('''
fff() {
  return 42;
}
''');
    await assertHasAssistAt(
        '{', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
fff() => 42;
''');
  }

  test_convertToExpressionBody_OK_function_onName() async {
    await resolveTestUnit('''
fff() {
  return 42;
}
''');
    await assertHasAssistAt(
        'ff()', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
fff() => 42;
''');
  }

  test_convertToExpressionBody_OK_method_onBlock() async {
    await resolveTestUnit('''
class A {
  m() { // marker
    return 42;
  }
}
''');
    await assertHasAssistAt(
        '{ // marker', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
class A {
  m() => 42;
}
''');
  }

  test_convertToExpressionBody_OK_topFunction_onReturnStatement() async {
    await resolveTestUnit('''
fff() {
  return 42;
}
''');
    await assertHasAssistAt(
        'return', DartAssistKind.CONVERT_INTO_EXPRESSION_BODY, '''
fff() => 42;
''');
  }

  test_convertToFieldParameter_BAD_additionalUse() async {
    await resolveTestUnit('''
class A {
  int aaa2;
  int bbb2;
  A(int aaa) : aaa2 = aaa, bbb2 = aaa;
}
''');
    await assertNoAssistAt('aaa)', DartAssistKind.CONVERT_TO_FIELD_PARAMETER);
  }

  test_convertToFieldParameter_BAD_notPureAssignment() async {
    await resolveTestUnit('''
class A {
  int aaa2;
  A(int aaa) : aaa2 = aaa * 2;
}
''');
    await assertNoAssistAt('aaa)', DartAssistKind.CONVERT_TO_FIELD_PARAMETER);
  }

  test_convertToFieldParameter_OK_firstInitializer() async {
    await resolveTestUnit('''
class A {
  int aaa2;
  int bbb2;
  A(int aaa, int bbb) : aaa2 = aaa, bbb2 = bbb;
}
''');
    await assertHasAssistAt(
        'aaa, ', DartAssistKind.CONVERT_TO_FIELD_PARAMETER, '''
class A {
  int aaa2;
  int bbb2;
  A(this.aaa2, int bbb) : bbb2 = bbb;
}
''');
  }

  test_convertToFieldParameter_OK_onParameterName_inInitializer() async {
    await resolveTestUnit('''
class A {
  int test2;
  A(int test) : test2 = test {
  }
}
''');
    await assertHasAssistAt(
        'test {', DartAssistKind.CONVERT_TO_FIELD_PARAMETER, '''
class A {
  int test2;
  A(this.test2) {
  }
}
''');
  }

  test_convertToFieldParameter_OK_onParameterName_inParameters() async {
    await resolveTestUnit('''
class A {
  int test;
  A(int test) : test = test {
  }
}
''');
    await assertHasAssistAt(
        'test)', DartAssistKind.CONVERT_TO_FIELD_PARAMETER, '''
class A {
  int test;
  A(this.test) {
  }
}
''');
  }

  test_convertToFieldParameter_OK_secondInitializer() async {
    await resolveTestUnit('''
class A {
  int aaa2;
  int bbb2;
  A(int aaa, int bbb) : aaa2 = aaa, bbb2 = bbb;
}
''');
    await assertHasAssistAt(
        'bbb)', DartAssistKind.CONVERT_TO_FIELD_PARAMETER, '''
class A {
  int aaa2;
  int bbb2;
  A(int aaa, this.bbb2) : aaa2 = aaa;
}
''');
  }

  test_convertToFinalField_BAD_hasSetter_inThisClass() async {
    await resolveTestUnit('''
class A {
  int get foo => null;
  void set foo(_) {}
}
''');
    await assertNoAssistAt('get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD);
  }

  test_convertToFinalField_BAD_notExpressionBody() async {
    await resolveTestUnit('''
class A {
  int get foo {
    int v = 1 + 2;
    return v + 3;
  }
}
''');
    await assertNoAssistAt('get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD);
  }

  test_convertToFinalField_BAD_notGetter() async {
    await resolveTestUnit('''
class A {
  int foo() => 42;
}
''');
    await assertNoAssistAt('foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD);
  }

  test_convertToFinalField_OK_blockBody_onlyReturnStatement() async {
    await resolveTestUnit('''
class A {
  int get foo {
    return 1 + 2;
  }
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final int foo = 1 + 2;
}
''');
  }

  test_convertToFinalField_OK_hasOverride() async {
    await resolveTestUnit('''
const myAnnotation = const Object();
class A {
  @myAnnotation
  int get foo => 42;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
const myAnnotation = const Object();
class A {
  @myAnnotation
  final int foo = 42;
}
''');
  }

  test_convertToFinalField_OK_hasSetter_inSuper() async {
    await resolveTestUnit('''
class A {
  void set foo(_) {}
}
class B extends A {
  int get foo => null;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  void set foo(_) {}
}
class B extends A {
  final int foo;
}
''');
  }

  test_convertToFinalField_OK_noReturnType() async {
    await resolveTestUnit('''
class A {
  get foo => 42;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final foo = 42;
}
''');
  }

  test_convertToFinalField_OK_noReturnType_static() async {
    await resolveTestUnit('''
class A {
  static get foo => 42;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  static final foo = 42;
}
''');
  }

  test_convertToFinalField_OK_notNull() async {
    await resolveTestUnit('''
class A {
  int get foo => 1 + 2;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final int foo = 1 + 2;
}
''');
  }

  test_convertToFinalField_OK_null() async {
    await resolveTestUnit('''
class A {
  int get foo => null;
}
''');
    await assertHasAssistAt(
        'get foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final int foo;
}
''');
  }

  test_convertToFinalField_OK_onName() async {
    await resolveTestUnit('''
class A {
  int get foo => 42;
}
''');
    await assertHasAssistAt('foo', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final int foo = 42;
}
''');
  }

  test_convertToFinalField_OK_onReturnType_parameterized() async {
    await resolveTestUnit('''
class A {
  List<int> get foo => null;
}
''');
    await assertHasAssistAt(
        'nt> get', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final List<int> foo;
}
''');
  }

  test_convertToFinalField_OK_onReturnType_simple() async {
    await resolveTestUnit('''
class A {
  int get foo => 42;
}
''');
    await assertHasAssistAt(
        'int get', DartAssistKind.CONVERT_INTO_FINAL_FIELD, '''
class A {
  final int foo = 42;
}
''');
  }

  test_convertToForIndex_BAD_bodyNotBlock() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) print(item);
}
''');
    await assertNoAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX);
  }

  test_convertToForIndex_BAD_doesNotDeclareVariable() async {
    await resolveTestUnit('''
main(List<String> items) {
  String item;
  for (item in items) {
    print(item);
  }
}
''');
    await assertNoAssistAt('for (item', DartAssistKind.CONVERT_INTO_FOR_INDEX);
  }

  test_convertToForIndex_BAD_iterableIsNotVariable() async {
    await resolveTestUnit('''
main() {
  for (String item in ['a', 'b', 'c']) {
    print(item);
  }
}
''');
    await assertNoAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX);
  }

  test_convertToForIndex_BAD_iterableNotList() async {
    await resolveTestUnit('''
main(Iterable<String> items) {
  for (String item in items) {
    print(item);
  }
}
''');
    await assertNoAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX);
  }

  test_convertToForIndex_BAD_usesIJK() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    print(item);
    int i, j, k;
  }
}
''');
    await assertNoAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX);
  }

  test_convertToForIndex_OK_onDeclaredIdentifier_name() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    print(item);
  }
}
''');
    await assertHasAssistAt(
        'item in', DartAssistKind.CONVERT_INTO_FOR_INDEX, '''
main(List<String> items) {
  for (int i = 0; i < items.length; i++) {
    String item = items[i];
    print(item);
  }
}
''');
  }

  test_convertToForIndex_OK_onDeclaredIdentifier_type() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    print(item);
  }
}
''');
    await assertHasAssistAt(
        'tring item', DartAssistKind.CONVERT_INTO_FOR_INDEX, '''
main(List<String> items) {
  for (int i = 0; i < items.length; i++) {
    String item = items[i];
    print(item);
  }
}
''');
  }

  test_convertToForIndex_OK_onFor() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    print(item);
  }
}
''');
    await assertHasAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX, '''
main(List<String> items) {
  for (int i = 0; i < items.length; i++) {
    String item = items[i];
    print(item);
  }
}
''');
  }

  test_convertToForIndex_OK_usesI() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    int i = 0;
  }
}
''');
    await assertHasAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX, '''
main(List<String> items) {
  for (int j = 0; j < items.length; j++) {
    String item = items[j];
    int i = 0;
  }
}
''');
  }

  test_convertToForIndex_OK_usesIJ() async {
    await resolveTestUnit('''
main(List<String> items) {
  for (String item in items) {
    print(item);
    int i = 0, j = 1;
  }
}
''');
    await assertHasAssistAt(
        'for (String', DartAssistKind.CONVERT_INTO_FOR_INDEX, '''
main(List<String> items) {
  for (int k = 0; k < items.length; k++) {
    String item = items[k];
    print(item);
    int i = 0, j = 1;
  }
}
''');
  }

  test_convertToFunctionSyntax_BAD_functionTypeAlias_insideParameterList() async {
    await resolveTestUnit('''
typedef String F(int x, int y);
''');
    await assertNoAssistAt(
        'x,', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX);
  }

  test_convertToFunctionSyntax_BAD_functionTypeAlias_noParameterTypes() async {
    await resolveTestUnit('''
typedef String F(x);
''');
    await assertNoAssistAt(
        'def', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX);
  }

  test_convertToFunctionSyntax_BAD_functionTypedParameter_insideParameterList() async {
    await resolveTestUnit('''
g(String f(int x, int y)) {}
''');
    await assertNoAssistAt(
        'x,', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX);
  }

  test_convertToFunctionSyntax_BAD_functionTypedParameter_noParameterTypes() async {
    await resolveTestUnit('''
g(String f(x)) {}
''');
    await assertNoAssistAt(
        'f(', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX);
  }

  test_convertToFunctionSyntax_OK_functionTypeAlias_noReturnType_noTypeParameters() async {
    await resolveTestUnit('''
typedef String F(int x);
''');
    await assertHasAssistAt(
        'def', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
typedef F = String Function(int x);
''');
  }

  test_convertToFunctionSyntax_OK_functionTypeAlias_noReturnType_typeParameters() async {
    await resolveTestUnit('''
typedef F<P, R>(P x);
''');
    await assertHasAssistAt(
        'def', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
typedef F<P, R> = Function(P x);
''');
  }

  test_convertToFunctionSyntax_OK_functionTypeAlias_returnType_noTypeParameters() async {
    await resolveTestUnit('''
typedef String F(int x);
''');
    await assertHasAssistAt(
        'def', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
typedef F = String Function(int x);
''');
  }

  test_convertToFunctionSyntax_OK_functionTypeAlias_returnType_typeParameters() async {
    await resolveTestUnit('''
typedef R F<P, R>(P x);
''');
    await assertHasAssistAt(
        'def', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
typedef F<P, R> = R Function(P x);
''');
  }

  test_convertToFunctionSyntax_OK_functionTypedParameter_noReturnType_noTypeParameters() async {
    await resolveTestUnit('''
g(f(int x)) {}
''');
    await assertHasAssistAt(
        'f(', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
g(Function(int x) f) {}
''');
  }

  test_convertToFunctionSyntax_OK_functionTypedParameter_returnType() async {
    await resolveTestUnit('''
g(String f(int x)) {}
''');
    await assertHasAssistAt(
        'f(', DartAssistKind.CONVERT_INTO_GENERIC_FUNCTION_SYNTAX, '''
g(String Function(int x) f) {}
''');
  }

  test_convertToGetter_BAD_noInitializer() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
class A {
  final int foo;
}
''');
    await assertNoAssistAt('foo', DartAssistKind.CONVERT_INTO_GETTER);
  }

  test_convertToGetter_BAD_notFinal() async {
    await resolveTestUnit('''
class A {
  int foo = 1;
}
''');
    await assertNoAssistAt('foo', DartAssistKind.CONVERT_INTO_GETTER);
  }

  test_convertToGetter_BAD_notSingleField() async {
    await resolveTestUnit('''
class A {
  final int foo = 1, bar = 2;
}
''');
    await assertNoAssistAt('foo', DartAssistKind.CONVERT_INTO_GETTER);
  }

  test_convertToGetter_OK() async {
    await resolveTestUnit('''
const myAnnotation = const Object();
class A {
  @myAnnotation
  final int foo = 1 + 2;
}
''');
    await assertHasAssistAt('foo =', DartAssistKind.CONVERT_INTO_GETTER, '''
const myAnnotation = const Object();
class A {
  @myAnnotation
  int get foo => 1 + 2;
}
''');
  }

  test_convertToGetter_OK_noType() async {
    await resolveTestUnit('''
class A {
  final foo = 42;
}
''');
    await assertHasAssistAt('foo =', DartAssistKind.CONVERT_INTO_GETTER, '''
class A {
  get foo => 42;
}
''');
  }

  test_convertToIsNot_BAD_is_alreadyIsNot() async {
    await resolveTestUnit('''
main(p) {
  p is! String;
}
''');
    await assertNoAssistAt('is!', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_is_noEnclosingParenthesis() async {
    await resolveTestUnit('''
main(p) {
  p is String;
}
''');
    await assertNoAssistAt('is String', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_is_noPrefix() async {
    await resolveTestUnit('''
main(p) {
  (p is String);
}
''');
    await assertNoAssistAt('is String', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_is_notIsExpression() async {
    await resolveTestUnit('''
main(p) {
  123 + 456;
}
''');
    await assertNoAssistAt('123 +', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_is_notTheNotOperator() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main(p) {
  ++(p is String);
}
''');
    await assertNoAssistAt('is String', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_not_alreadyIsNot() async {
    await resolveTestUnit('''
main(p) {
  !(p is! String);
}
''');
    await assertNoAssistAt('!(p', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_not_noEnclosingParenthesis() async {
    await resolveTestUnit('''
main(p) {
  !p;
}
''');
    await assertNoAssistAt('!p', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_not_notIsExpression() async {
    await resolveTestUnit('''
main(p) {
  !(p == null);
}
''');
    await assertNoAssistAt('!(p', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_BAD_not_notTheNotOperator() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main(p) {
  ++(p is String);
}
''');
    await assertNoAssistAt('++(', DartAssistKind.CONVERT_INTO_IS_NOT);
  }

  test_convertToIsNot_OK_childOfIs_left() async {
    await resolveTestUnit('''
main(p) {
  !(p is String);
}
''');
    await assertHasAssistAt('p is', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  p is! String;
}
''');
  }

  test_convertToIsNot_OK_childOfIs_right() async {
    await resolveTestUnit('''
main(p) {
  !(p is String);
}
''');
    await assertHasAssistAt('String)', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  p is! String;
}
''');
  }

  test_convertToIsNot_OK_is() async {
    await resolveTestUnit('''
main(p) {
  !(p is String);
}
''');
    await assertHasAssistAt('is String', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  p is! String;
}
''');
  }

  test_convertToIsNot_OK_is_higherPrecedencePrefix() async {
    await resolveTestUnit('''
main(p) {
  !!(p is String);
}
''');
    await assertHasAssistAt('is String', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  !(p is! String);
}
''');
  }

  test_convertToIsNot_OK_is_not_higherPrecedencePrefix() async {
    await resolveTestUnit('''
main(p) {
  !!(p is String);
}
''');
    await assertHasAssistAt('!(p', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  !(p is! String);
}
''');
  }

  test_convertToIsNot_OK_not() async {
    await resolveTestUnit('''
main(p) {
  !(p is String);
}
''');
    await assertHasAssistAt('!(p', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  p is! String;
}
''');
  }

  test_convertToIsNot_OK_parentheses() async {
    await resolveTestUnit('''
main(p) {
  !(p is String);
}
''');
    await assertHasAssistAt('(p is', DartAssistKind.CONVERT_INTO_IS_NOT, '''
main(p) {
  p is! String;
}
''');
  }

  test_convertToIsNotEmpty_BAD_noBang() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main(String str) {
  ~str.isEmpty;
}
''');
    await assertNoAssistAt(
        'isEmpty;', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY);
  }

  test_convertToIsNotEmpty_BAD_noIsNotEmpty() async {
    await resolveTestUnit('''
class A {
  bool get isEmpty => false;
}
main(A a) {
  !a.isEmpty;
}
''');
    await assertNoAssistAt(
        'isEmpty;', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY);
  }

  test_convertToIsNotEmpty_BAD_notInPrefixExpression() async {
    await resolveTestUnit('''
main(String str) {
  str.isEmpty;
}
''');
    await assertNoAssistAt(
        'isEmpty;', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY);
  }

  test_convertToIsNotEmpty_BAD_notIsEmpty() async {
    await resolveTestUnit('''
main(int p) {
  !p.isEven;
}
''');
    await assertNoAssistAt('isEven;', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY);
  }

  test_convertToIsNotEmpty_OK_on_isEmpty() async {
    await resolveTestUnit('''
main(String str) {
  !str.isEmpty;
}
''');
    await assertHasAssistAt(
        'isEmpty', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY, '''
main(String str) {
  str.isNotEmpty;
}
''');
  }

  test_convertToIsNotEmpty_OK_on_str() async {
    await resolveTestUnit('''
main(String str) {
  !str.isEmpty;
}
''');
    await assertHasAssistAt(
        'str.', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY, '''
main(String str) {
  str.isNotEmpty;
}
''');
  }

  test_convertToIsNotEmpty_OK_propertyAccess() async {
    await resolveTestUnit('''
main(String str) {
  !'text'.isEmpty;
}
''');
    await assertHasAssistAt(
        'isEmpty', DartAssistKind.CONVERT_INTO_IS_NOT_EMPTY, '''
main(String str) {
  'text'.isNotEmpty;
}
''');
  }

  test_convertToNormalParameter_OK_dynamic() async {
    await resolveTestUnit('''
class A {
  var test;
  A(this.test) {
  }
}
''');
    await assertHasAssistAt(
        'test)', DartAssistKind.CONVERT_TO_NORMAL_PARAMETER, '''
class A {
  var test;
  A(test) : test = test {
  }
}
''');
  }

  test_convertToNormalParameter_OK_firstInitializer() async {
    await resolveTestUnit('''
class A {
  int test;
  A(this.test) {
  }
}
''');
    await assertHasAssistAt(
        'test)', DartAssistKind.CONVERT_TO_NORMAL_PARAMETER, '''
class A {
  int test;
  A(int test) : test = test {
  }
}
''');
  }

  test_convertToNormalParameter_OK_secondInitializer() async {
    await resolveTestUnit('''
class A {
  double aaa;
  int bbb;
  A(this.bbb) : aaa = 1.0;
}
''');
    await assertHasAssistAt(
        'bbb)', DartAssistKind.CONVERT_TO_NORMAL_PARAMETER, '''
class A {
  double aaa;
  int bbb;
  A(int bbb) : aaa = 1.0, bbb = bbb;
}
''');
  }

  test_convertToSingleQuotedString_BAD_one_embeddedTarget() async {
    await resolveTestUnit('''
main() {
  print("a'b'c");
}
''');
    await assertNoAssistAt(
        '"a', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING);
  }

  test_convertToSingleQuotedString_BAD_one_enclosingTarget() async {
    await resolveTestUnit('''
main() {
  print('abc');
}
''');
    await assertNoAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING);
  }

  test_convertToSingleQuotedString_BAD_three_embeddedTarget() async {
    await resolveTestUnit('''
main() {
  print("""a''\'bc""");
}
''');
    await assertNoAssistAt(
        '"a', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING);
  }

  test_convertToSingleQuotedString_BAD_three_enclosingTarget() async {
    await resolveTestUnit("""
main() {
  print('''abc''');
}
""");
    await assertNoAssistAt(
        "'ab", DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING);
  }

  test_convertToSingleQuotedString_OK_one_interpolation() async {
    await resolveTestUnit(r'''
main() {
  var b = 'b';
  var c = 'c';
  print("a $b-${c} d");
}
''');
    await assertHasAssistAt(
        r'"a $b', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, r'''
main() {
  var b = 'b';
  var c = 'c';
  print('a $b-${c} d');
}
''');
  }

  test_convertToSingleQuotedString_OK_one_raw() async {
    await resolveTestUnit('''
main() {
  print(r"abc");
}
''');
    await assertHasAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, '''
main() {
  print(r'abc');
}
''');
  }

  test_convertToSingleQuotedString_OK_one_simple() async {
    await resolveTestUnit('''
main() {
  print("abc");
}
''');
    await assertHasAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, '''
main() {
  print('abc');
}
''');
  }

  test_convertToSingleQuotedString_OK_three_interpolation() async {
    await resolveTestUnit(r'''
main() {
  var b = 'b';
  var c = 'c';
  print("""a $b-${c} d""");
}
''');
    await assertHasAssistAt(
        r'"a $b', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, r"""
main() {
  var b = 'b';
  var c = 'c';
  print('''a $b-${c} d''');
}
""");
  }

  test_convertToSingleQuotedString_OK_three_raw() async {
    await resolveTestUnit('''
main() {
  print(r"""abc""");
}
''');
    await assertHasAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, """
main() {
  print(r'''abc''');
}
""");
  }

  test_convertToSingleQuotedString_OK_three_simple() async {
    await resolveTestUnit('''
main() {
  print("""abc""");
}
''');
    await assertHasAssistAt(
        '"ab', DartAssistKind.CONVERT_TO_SINGLE_QUOTED_STRING, """
main() {
  print('''abc''');
}
""");
  }

  test_encapsulateField_BAD_alreadyPrivate() async {
    await resolveTestUnit('''
class A {
  int _test = 42;
}
main(A a) {
  print(a._test);
}
''');
    await assertNoAssistAt('_test =', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_BAD_final() async {
    await resolveTestUnit('''
class A {
  final int test = 42;
}
''');
    await assertNoAssistAt('test =', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_BAD_multipleFields() async {
    await resolveTestUnit('''
class A {
  int aaa, bbb, ccc;
}
main(A a) {
  print(a.bbb);
}
''');
    await assertNoAssistAt('bbb, ', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_BAD_notOnName() async {
    await resolveTestUnit('''
class A {
  int test = 1 + 2 + 3;
}
''');
    await assertNoAssistAt('+ 2', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_BAD_parseError() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
class A {
  int; // marker
}
main(A a) {
  print(a.test);
}
''');
    await assertNoAssistAt('; // marker', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_BAD_static() async {
    await resolveTestUnit('''
class A {
  static int test = 42;
}
''');
    await assertNoAssistAt('test =', DartAssistKind.ENCAPSULATE_FIELD);
  }

  test_encapsulateField_OK_documentation() async {
    await resolveTestUnit('''
class A {
  /// AAA
  /// BBB
  int test;
}
''');
    await assertHasAssistAt('test;', DartAssistKind.ENCAPSULATE_FIELD, '''
class A {
  /// AAA
  /// BBB
  int _test;

  /// AAA
  /// BBB
  int get test => _test;

  /// AAA
  /// BBB
  set test(int test) {
    _test = test;
  }
}
''');
  }

  test_encapsulateField_OK_hasType() async {
    await resolveTestUnit('''
class A {
  int test = 42;
  A(this.test);
}
main(A a) {
  print(a.test);
}
''');
    await assertHasAssistAt('test = 42', DartAssistKind.ENCAPSULATE_FIELD, '''
class A {
  int _test = 42;

  int get test => _test;

  set test(int test) {
    _test = test;
  }
  A(this._test);
}
main(A a) {
  print(a.test);
}
''');
  }

  test_encapsulateField_OK_noType() async {
    await resolveTestUnit('''
class A {
  var test = 42;
}
main(A a) {
  print(a.test);
}
''');
    await assertHasAssistAt('test = 42', DartAssistKind.ENCAPSULATE_FIELD, '''
class A {
  var _test = 42;

  get test => _test;

  set test(test) {
    _test = test;
  }
}
main(A a) {
  print(a.test);
}
''');
  }

  test_exchangeBinaryExpressionArguments_BAD_extraLength() async {
    await resolveTestUnit('''
main() {
  111 + 222;
}
''');
    length = 3;
    await assertNoAssistAt('+ 222', DartAssistKind.EXCHANGE_OPERANDS);
  }

  test_exchangeBinaryExpressionArguments_BAD_onOperand() async {
    await resolveTestUnit('''
main() {
  111 + 222;
}
''');
    length = 3;
    await assertNoAssistAt('11 +', DartAssistKind.EXCHANGE_OPERANDS);
  }

  test_exchangeBinaryExpressionArguments_BAD_selectionWithBinary() async {
    await resolveTestUnit('''
main() {
  1 + 2 + 3;
}
''');
    length = '1 + 2 + 3'.length;
    await assertNoAssistAt('1 + 2 + 3', DartAssistKind.EXCHANGE_OPERANDS);
  }

  test_exchangeBinaryExpressionArguments_OK_compare() async {
    const initialOperators = const ['<', '<=', '>', '>='];
    const resultOperators = const ['>', '>=', '<', '<='];
    for (int i = 0; i <= 0; i++) {
      String initialOperator = initialOperators[i];
      String resultOperator = resultOperators[i];
      await resolveTestUnit('''
bool main(int a, int b) {
  return a $initialOperator b;
}
''');
      await assertHasAssistAt(
          initialOperator, DartAssistKind.EXCHANGE_OPERANDS, '''
bool main(int a, int b) {
  return b $resultOperator a;
}
''');
    }
  }

  test_exchangeBinaryExpressionArguments_OK_extended_mixOperator_1() async {
    await resolveTestUnit('''
main() {
  1 * 2 * 3 + 4;
}
''');
    await assertHasAssistAt('* 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 * 3 * 1 + 4;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_extended_mixOperator_2() async {
    await resolveTestUnit('''
main() {
  1 + 2 - 3 + 4;
}
''');
    await assertHasAssistAt('+ 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 1 - 3 + 4;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_extended_sameOperator_afterFirst() async {
    await resolveTestUnit('''
main() {
  1 + 2 + 3;
}
''');
    await assertHasAssistAt('+ 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 3 + 1;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_extended_sameOperator_afterSecond() async {
    await resolveTestUnit('''
main() {
  1 + 2 + 3;
}
''');
    await assertHasAssistAt('+ 3', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  3 + 1 + 2;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_simple_afterOperator() async {
    await resolveTestUnit('''
main() {
  1 + 2;
}
''');
    await assertHasAssistAt(' 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 1;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_simple_beforeOperator() async {
    await resolveTestUnit('''
main() {
  1 + 2;
}
''');
    await assertHasAssistAt('+ 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 1;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_simple_fullSelection() async {
    await resolveTestUnit('''
main() {
  1 + 2;
}
''');
    length = '1 + 2'.length;
    await assertHasAssistAt('1 + 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 1;
}
''');
  }

  test_exchangeBinaryExpressionArguments_OK_simple_withLength() async {
    await resolveTestUnit('''
main() {
  1 + 2;
}
''');
    length = 2;
    await assertHasAssistAt('+ 2', DartAssistKind.EXCHANGE_OPERANDS, '''
main() {
  2 + 1;
}
''');
  }

  test_flutterConvertToChildren_BAD_childUnresolved() async {
    addFlutterPackage();
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Row(
    /*caret*/child: new Container()
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_CONVERT_TO_CHILDREN);
  }

  test_flutterConvertToChildren_BAD_notOnChild() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
    body: /*caret*/new Center(
      child: new Container(),
    ),
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_CONVERT_TO_CHILDREN);
  }

  test_flutterConvertToChildren_OK_multiLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/child: new Container(
        width: 200.0,
        height: 300.0,
      ),
      key: null,
    ),
// end
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_CONVERT_TO_CHILDREN, '''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/children: <Widget>[
        new Container(
          width: 200.0,
          height: 300.0,
        ),
      ],
      key: null,
    ),
// end
  );
}
''');
  }

  test_flutterConvertToChildren_OK_newlineChild() async {
    // This case could occur with deeply nested constructors, common in Flutter.
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/child:
          new Container(
        width: 200.0,
        height: 300.0,
      ),
      key: null,
    ),
// end
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_CONVERT_TO_CHILDREN, '''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/children: <Widget>[
        new Container(
          width: 200.0,
          height: 300.0,
        ),
      ],
      key: null,
    ),
// end
  );
}
''');
  }

  test_flutterConvertToChildren_OK_singleLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/child: new GestureDetector(),
      key: null,
    ),
// end
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_CONVERT_TO_CHILDREN, '''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      /*caret*/children: <Widget>[new GestureDetector()],
      key: null,
    ),
// end
  );
}
''');
  }

  test_flutterConvertToStatefulWidget_BAD_notClass() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
/*caret*/main() {}
''');
    _setCaretLocation();
    assertNoAssist(DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET);
  }

  test_flutterConvertToStatefulWidget_BAD_notStatelessWidget() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
class /*caret*/MyWidget extends Text {
  MyWidget() : super('');
}
''');
    _setCaretLocation();
    assertNoAssist(DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET);
  }

  test_flutterConvertToStatefulWidget_BAD_notWidget() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
class /*caret*/MyWidget {}
''');
    _setCaretLocation();
    assertNoAssist(DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET);
  }

  test_flutterConvertToStatefulWidget_OK() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  final String aaa;
  final String bbb;

  const MyWidget(this.aaa, this.bbb);

  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(aaa),
        new Text(bbb),
        new Text('$aaa'),
        new Text('${bbb}'),
      ],
    );
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  final String aaa;
  final String bbb;

  const MyWidget(this.aaa, this.bbb);

  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }
}

class MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(widget.aaa),
        new Text(widget.bbb),
        new Text('${widget.aaa}'),
        new Text('${widget.bbb}'),
      ],
    );
  }
}
''');
  }

  test_flutterConvertToStatefulWidget_OK_empty() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Container();
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }
}

class MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return new Container();
  }
}
''');
  }

  test_flutterConvertToStatefulWidget_OK_fields() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  static String staticField1;
  final String instanceField1;
  final String instanceField2;
  String instanceField3;
  static String staticField2;
  String instanceField4;
  String instanceField5;
  static String staticField3;

  MyWidget(this.instanceField1) : instanceField2 = '' {
    instanceField3 = '';
  }

  @override
  Widget build(BuildContext context) {
    instanceField4 = instanceField1;
    return new Row(
      children: [
        new Text(instanceField1),
        new Text(instanceField2),
        new Text(instanceField3),
        new Text(instanceField4),
        new Text(instanceField5),
        new Text(staticField1),
        new Text(staticField2),
        new Text(staticField3),
      ],
    );
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  static String staticField1;
  final String instanceField1;
  final String instanceField2;
  String instanceField3;
  static String staticField2;
  static String staticField3;

  MyWidget(this.instanceField1) : instanceField2 = '' {
    instanceField3 = '';
  }

  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }
}

class MyWidgetState extends State<MyWidget> {
  String instanceField4;

  String instanceField5;

  @override
  Widget build(BuildContext context) {
    instanceField4 = widget.instanceField1;
    return new Row(
      children: [
        new Text(widget.instanceField1),
        new Text(widget.instanceField2),
        new Text(widget.instanceField3),
        new Text(instanceField4),
        new Text(instanceField5),
        new Text(MyWidget.staticField1),
        new Text(MyWidget.staticField2),
        new Text(MyWidget.staticField3),
      ],
    );
  }
}
''');
  }

  test_flutterConvertToStatefulWidget_OK_getters() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(staticGetter1),
        new Text(staticGetter2),
        new Text(instanceGetter1),
        new Text(instanceGetter2),
      ],
    );
  }

  static String get staticGetter1 => '';

  String get instanceGetter1 => '';

  static String get staticGetter2 => '';

  String get instanceGetter2 => '';
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }

  static String get staticGetter1 => '';

  static String get staticGetter2 => '';
}

class MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(MyWidget.staticGetter1),
        new Text(MyWidget.staticGetter2),
        new Text(instanceGetter1),
        new Text(instanceGetter2),
      ],
    );
  }

  String get instanceGetter1 => '';

  String get instanceGetter2 => '';
}
''');
  }

  test_flutterConvertToStatefulWidget_OK_methods() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  static String staticField;
  final String instanceField1;
  String instanceField2;

  MyWidget(this.instanceField1);

  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(instanceField1),
        new Text(instanceField2),
        new Text(staticField),
      ],
    );
  }

  void instanceMethod1() {
    instanceMethod1();
    instanceMethod2();
    staticMethod1();
  }

  static void staticMethod1() {
    print('static 1');
  }

  void instanceMethod2() {
    print('instance 2');
  }

  static void staticMethod2() {
    print('static 2');
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  static String staticField;
  final String instanceField1;

  MyWidget(this.instanceField1);

  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }

  static void staticMethod1() {
    print('static 1');
  }

  static void staticMethod2() {
    print('static 2');
  }
}

class MyWidgetState extends State<MyWidget> {
  String instanceField2;

  @override
  Widget build(BuildContext context) {
    return new Row(
      children: [
        new Text(widget.instanceField1),
        new Text(instanceField2),
        new Text(MyWidget.staticField),
      ],
    );
  }

  void instanceMethod1() {
    instanceMethod1();
    instanceMethod2();
    MyWidget.staticMethod1();
  }

  void instanceMethod2() {
    print('instance 2');
  }
}
''');
  }

  test_flutterConvertToStatefulWidget_OK_tail() async {
    addFlutterPackage();
    await resolveTestUnit(r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Container();
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(
        DartAssistKind.FLUTTER_CONVERT_TO_STATEFUL_WIDGET, r'''
import 'package:flutter/material.dart';

class /*caret*/MyWidget extends StatefulWidget {
  @override
  MyWidgetState createState() {
    return new MyWidgetState();
  }
}

class MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return new Container();
  }
}
''');
  }

  test_flutterMoveWidgetDown_BAD_last() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      new Text('bbb'),
      /*caret*/new Text('ccc'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_MOVE_DOWN);
  }

  test_flutterMoveWidgetDown_BAD_notInList() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Center(
    child: /*caret*/new Text('aaa'),
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_MOVE_DOWN);
  }

  test_flutterMoveWidgetDown_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      /*caret*/new Text('bbbbbb'),
      new Text('ccccccccc'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_MOVE_DOWN, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      /*caret*/new Text('ccccccccc'),
      new Text('bbbbbb'),
    ],
  );
}
''');
    _assertExitPosition(before: "new Text('bbbbbb')");
  }

  test_flutterMoveWidgetUp_BAD_first() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      /*caret*/new Text('aaa'),
      new Text('bbb'),
      new Text('ccc'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_MOVE_UP);
  }

  test_flutterMoveWidgetUp_BAD_notInList() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Center(
    child: /*caret*/new Text('aaa'),
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_MOVE_UP);
  }

  test_flutterMoveWidgetUp_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      /*caret*/new Text('bbbbbb'),
      new Text('ccccccccc'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_MOVE_UP, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('bbbbbb'),
      /*caret*/new Text('aaa'),
      new Text('ccccccccc'),
    ],
  );
}
''');
    _assertExitPosition(before: "new Text('bbbbbb')");
  }

  test_flutterRemoveWidget_BAD_childrenMultipleIntoChild() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Center(
    child: new /*caret*/Row(
      children: [
        new Text('aaa'),
        new Text('bbb'),
      ],
    ),
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET);
  }

  test_flutterRemoveWidget_OK_childIntoChild_multiLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Center(
        child: new /*caret*/Padding(
          padding: const EdgeInsets.all(8.0),
          child: new Center(
            heightFactor: 0.5,
            child: new Text('foo'),
          ),
        ),
      ),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Center(
        child: new Center(
          heightFactor: 0.5,
          child: new Text('foo'),
        ),
      ),
    ],
  );
}
''');
  }

  test_flutterRemoveWidget_OK_childIntoChild_singleLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Padding(
    padding: const EdgeInsets.all(8.0),
    child: new /*caret*/Center(
      heightFactor: 0.5,
      child: new Text('foo'),
    ),
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  new Padding(
    padding: const EdgeInsets.all(8.0),
    child: new Text('foo'),
  );
}
''');
  }

  test_flutterRemoveWidget_OK_childIntoChildren() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('foo'),
      new /*caret*/Center(
        heightFactor: 0.5,
        child: new Padding(
          padding: const EdgeInsets.all(8.0),
          child: new Text('bar'),
        ),
      ),
      new Text('baz'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('foo'),
      new Padding(
        padding: const EdgeInsets.all(8.0),
        child: new Text('bar'),
      ),
      new Text('baz'),
    ],
  );
}
''');
  }

  test_flutterRemoveWidget_OK_childrenOneIntoChild() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Center(
    child: /*caret*/new Column(
      children: [
        new Text('foo'),
      ],
    ),
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  new Center(
    child: /*caret*/new Text('foo'),
  );
}
''');
  }

  test_flutterRemoveWidget_OK_childrenOneIntoReturn() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  return /*caret*/new Column(
    children: [
      new Text('foo'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  return /*caret*/new Text('foo');
}
''');
  }

  test_flutterRemoveWidget_OK_intoChildren() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      new /*caret*/Column(
        children: [
          new Row(
            children: [
              new Text('bbb'),
              new Text('ccc'),
            ],
          ),
          new Row(
            children: [
              new Text('ddd'),
              new Text('eee'),
            ],
          ),
        ],
      ),
      new Text('fff'),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_REMOVE_WIDGET, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: <Widget>[
      new Text('aaa'),
      new Row(
        children: [
          new Text('bbb'),
          new Text('ccc'),
        ],
      ),
      new Row(
        children: [
          new Text('ddd'),
          new Text('eee'),
        ],
      ),
      new Text('fff'),
    ],
  );
}
''');
  }

  test_flutterSwapWithChild_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new /*caret*/GestureDetector(
      onTap: () => startResize(),
      child: new Center(
        child: new Container(
          width: 200.0,
          height: 300.0,
        ),
        key: null,
      ),
    ),
// end
  );
}
startResize() {}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_SWAP_WITH_CHILD, '''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      key: null,
      child: new /*caret*/GestureDetector(
        onTap: () => startResize(),
        child: new Container(
          width: 200.0,
          height: 300.0,
        ),
      ),
    ),
// end
  );
}
startResize() {}
''');
  }

  test_flutterSwapWithChild_OK_notFormatted() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';

class Foo extends StatefulWidget {
  @override
  _State createState() => new _State();
}

class _State extends State<Foo> {
  @override
  Widget build(BuildContext context) {
    return new /*caret*/Expanded(
      flex: 2,
      child: new GestureDetector(
        child: new Text(
          'foo',
        ), onTap: () {
          print(42);
      },
      ),
    );
  }
}''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_SWAP_WITH_CHILD, '''
import 'package:flutter/material.dart';

class Foo extends StatefulWidget {
  @override
  _State createState() => new _State();
}

class _State extends State<Foo> {
  @override
  Widget build(BuildContext context) {
    return new GestureDetector(
      onTap: () {
        print(42);
    },
      child: new /*caret*/Expanded(
        flex: 2,
        child: new Text(
          'foo',
        ),
      ),
    );
  }
}''');
  }

  test_flutterSwapWithParent_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new Center(
      child: new /*caret*/GestureDetector(
        onTap: () => startResize(),
        child: new Container(
          width: 200.0,
          height: 300.0,
        ),
      ),
      key: null,
    ),
// end
  );
}
startResize() {}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_SWAP_WITH_PARENT, '''
import 'package:flutter/material.dart';
build() {
  return new Scaffold(
// start
    body: new /*caret*/GestureDetector(
      onTap: () => startResize(),
      child: new Center(
        key: null,
        child: new Container(
          width: 200.0,
          height: 300.0,
        ),
      ),
    ),
// end
  );
}
startResize() {}
''');
  }

  test_flutterSwapWithParent_OK_notFormatted() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';

class Foo extends StatefulWidget {
  @override
  _State createState() => new _State();
}

class _State extends State<Foo> {
  @override
  Widget build(BuildContext context) {
    return new GestureDetector(
      child: new /*caret*/Expanded(
        child: new Text(
          'foo',
        ),
        flex: 2,
      ), onTap: () {
        print(42);
    },
    );
  }
}''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_SWAP_WITH_PARENT, '''
import 'package:flutter/material.dart';

class Foo extends StatefulWidget {
  @override
  _State createState() => new _State();
}

class _State extends State<Foo> {
  @override
  Widget build(BuildContext context) {
    return new /*caret*/Expanded(
      flex: 2,
      child: new GestureDetector(
        onTap: () {
          print(42);
      },
        child: new Text(
          'foo',
        ),
      ),
    );
  }
}''');
  }

  test_flutterSwapWithParent_OK_outerIsInChildren() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: [
      new Column(
        children: [
          new Padding(
            padding: new EdgeInsets.all(16.0),
            child: new /*caret*/Center(
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_SWAP_WITH_PARENT, '''
import 'package:flutter/material.dart';
main() {
  new Column(
    children: [
      new Column(
        children: [
          new /*caret*/Center(
            child: new Padding(
              padding: new EdgeInsets.all(16.0),
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
''');
  }

  test_flutterWrapCenter_BAD_onCenter() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Center();
  }
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_WRAP_CENTER);
  }

  test_flutterWrapCenter_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Container();
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_CENTER, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/Center(child: new Container());
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_CENTER, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Center(child: new Container());
  }
}
''');
    }
  }

  test_flutterWrapCenter_OK_implicitNew() async {
    configurePreviewDart2();
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/Container();
  }
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_WRAP_CENTER, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/Center(child: Container());
  }
}
''');
  }

  test_flutterWrapCenter_OK_namedConstructor() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';

class MyWidget extends StatelessWidget {
  MyWidget.named();

  Widget build(BuildContext context) => null;
}

main() {
  return MyWidget./*caret*/named();
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_CENTER, '''
import 'package:flutter/widgets.dart';

class MyWidget extends StatelessWidget {
  MyWidget.named();

  Widget build(BuildContext context) => null;
}

main() {
  return Center(child: MyWidget./*caret*/named());
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_CENTER, '''
import 'package:flutter/widgets.dart';

class MyWidget extends StatelessWidget {
  MyWidget.named();

  Widget build(BuildContext context) => null;
}

main() {
  return new Center(child: MyWidget./*caret*/named());
}
''');
    }
  }

  test_flutterWrapColumn_OK_coveredByWidget() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Container(
      child: new /*caret*/Text('aaa'),
    );
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_COLUMN, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Container(
      child: Column(
        children: <Widget>[
          new /*caret*/Text('aaa'),
        ],
      ),
    );
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_COLUMN, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Container(
      child: new Column(
        children: <Widget>[
          new /*caret*/Text('aaa'),
        ],
      ),
    );
  }
}
''');
    }
  }

  test_flutterWrapColumn_OK_coversWidgets() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Row(children: [
      new Text('aaa'),
// start
      new Text('bbb'),
      new Text('ccc'),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    _setStartEndSelection();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_COLUMN, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Row(children: [
      new Text('aaa'),
// start
      Column(
        children: <Widget>[
          new Text('bbb'),
          new Text('ccc'),
        ],
      ),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_COLUMN, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Row(children: [
      new Text('aaa'),
// start
      new Column(
        children: <Widget>[
          new Text('bbb'),
          new Text('ccc'),
        ],
      ),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    }
  }

  test_flutterWrapColumn_OK_implicitNew() async {
    configurePreviewDart2();
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';

main() {
  return Container(
    child: /*caret*/Text('aaa'),
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_WRAP_COLUMN, '''
import 'package:flutter/widgets.dart';

main() {
  return Container(
    child: /*caret*/Column(
      children: <Widget>[
        Text('aaa'),
      ],
    ),
  );
}
''');
  }

  test_flutterWrapPadding_BAD_onPadding() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Padding();
  }
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_WRAP_PADDING);
  }

  test_flutterWrapPadding_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Container();
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_PADDING, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/Padding(
      padding: const EdgeInsets.all(8.0),
      child: new Container(),
    );
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_PADDING, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return /*caret*/new Padding(
      padding: const EdgeInsets.all(8.0),
      child: new Container(),
    );
  }
}
''');
    }
  }

  test_flutterWrapRow_OK() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Column(children: [
      new Text('aaa'),
// start
      new Text('bbb'),
      new Text('ccc'),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    _setStartEndSelection();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_ROW, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Column(children: [
      new Text('aaa'),
// start
      Row(
        children: <Widget>[
          new Text('bbb'),
          new Text('ccc'),
        ],
      ),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_ROW, '''
import 'package:flutter/widgets.dart';

class FakeFlutter {
  main() {
    return new Column(children: [
      new Text('aaa'),
// start
      new Row(
        children: <Widget>[
          new Text('bbb'),
          new Text('ccc'),
        ],
      ),
// end
      new Text('ddd'),
    ]);
  }
}
''');
    }
  }

  test_flutterWrapWidget_BAD_minimal() async {
    addFlutterPackage();
    await resolveTestUnit('''
/*caret*/x(){}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_WRAP_GENERIC);
  }

  test_flutterWrapWidget_BAD_multiLine() async {
    verifyNoTestUnitErrors = false;
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
build() {
  return new Container(
    child: new Row(
      children: [/*caret*/
// start
        new Transform(),
        new Object(),
        new AspectRatio(),
// end
      ],
    ),
  );
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_WRAP_GENERIC);
  }

  test_flutterWrapWidget_BAD_singleLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
  var obj;
// start
    return new Row(children: [/*caret*/ new Container()]);
// end
  }
}
''');
    _setCaretLocation();
    await assertNoAssist(DartAssistKind.FLUTTER_WRAP_GENERIC);
  }

  test_flutterWrapWidget_OK_multiLine() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
build() {
  return new Container(
    child: new Row(
// start
      children: [/*caret*/
        new Text('111'),
        new Text('222'),
        new Container(),
      ],
// end
    ),
  );
}
''');
    _setCaretLocation();
    await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
build() {
  return new Container(
    child: new Row(
// start
      children: [
        new widget(
          children: [/*caret*/
            new Text('111'),
            new Text('222'),
            new Container(),
          ],
        ),
      ],
// end
    ),
  );
}
''');
  }

  test_flutterWrapWidget_OK_multiLines() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return new Container(
// start
      child: new /*caret*/DefaultTextStyle(
        child: new Row(
          children: <Widget>[
            new Container(
            ),
          ],
        ),
      ),
// end
    );
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return new Container(
// start
      child: widget(
        child: new /*caret*/DefaultTextStyle(
          child: new Row(
            children: <Widget>[
              new Container(
              ),
            ],
          ),
        ),
      ),
// end
    );
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return new Container(
// start
      child: new widget(
        child: new /*caret*/DefaultTextStyle(
          child: new Row(
            children: <Widget>[
              new Container(
              ),
            ],
          ),
        ),
      ),
// end
    );
  }
}
''');
    }
  }

  test_flutterWrapWidget_OK_multiLines_eol2() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {\r
  main() {\r
    return new Container(\r
// start\r
      child: new /*caret*/DefaultTextStyle(\r
        child: new Row(\r
          children: <Widget>[\r
            new Container(\r
            ),\r
          ],\r
        ),\r
      ),\r
// end\r
    );\r
  }\r
}\r
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {\r
  main() {\r
    return new Container(\r
// start\r
      child: widget(\r
        child: new /*caret*/DefaultTextStyle(\r
          child: new Row(\r
            children: <Widget>[\r
              new Container(\r
              ),\r
            ],\r
          ),\r
        ),\r
      ),\r
// end\r
    );\r
  }\r
}\r
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {\r
  main() {\r
    return new Container(\r
// start\r
      child: new widget(\r
        child: new /*caret*/DefaultTextStyle(\r
          child: new Row(\r
            children: <Widget>[\r
              new Container(\r
              ),\r
            ],\r
          ),\r
        ),\r
      ),\r
// end\r
    );\r
  }\r
}\r
''');
    }
  }

  test_flutterWrapWidget_OK_singleLine1() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
// start
    return /*caret*/new Container();
// end
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
// start
    return /*caret*/widget(child: new Container());
// end
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
// start
    return /*caret*/new widget(child: new Container());
// end
  }
}
''');
    }
  }

  test_flutterWrapWidget_OK_singleLine2() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return new ClipRect./*caret*/rect();
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return widget(child: new ClipRect./*caret*/rect());
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    return new widget(child: new ClipRect./*caret*/rect());
  }
}
''');
    }
  }

  test_flutterWrapWidget_OK_variable() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    var container = new Container();
    return /*caret*/container;
  }
}
''');
    _setCaretLocation();
    if (omitNew) {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    var container = new Container();
    return /*caret*/widget(child: container);
  }
}
''');
    } else {
      await assertHasAssist(DartAssistKind.FLUTTER_WRAP_GENERIC, '''
import 'package:flutter/widgets.dart';
class FakeFlutter {
  main() {
    var container = new Container();
    return /*caret*/new widget(child: container);
  }
}
''');
    }
  }

  test_importAddShow_BAD_hasShow() async {
    await resolveTestUnit('''
import 'dart:math' show PI;
main() {
  PI;
}
''');
    await assertNoAssistAt('import ', DartAssistKind.IMPORT_ADD_SHOW);
  }

  test_importAddShow_BAD_unresolvedUri() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
import '/no/such/lib.dart';
''');
    await assertNoAssistAt('import ', DartAssistKind.IMPORT_ADD_SHOW);
  }

  test_importAddShow_BAD_unused() async {
    await resolveTestUnit('''
import 'dart:math';
''');
    await assertNoAssistAt('import ', DartAssistKind.IMPORT_ADD_SHOW);
  }

  test_importAddShow_OK_hasUnresolvedIdentifier() async {
    await resolveTestUnit('''
import 'dart:math';
main(x) {
  PI;
  return x.foo();
}
''');
    await assertHasAssistAt('import ', DartAssistKind.IMPORT_ADD_SHOW, '''
import 'dart:math' show PI;
main(x) {
  PI;
  return x.foo();
}
''');
  }

  test_importAddShow_OK_onDirective() async {
    await resolveTestUnit('''
import 'dart:math';
main() {
  PI;
  E;
  max(1, 2);
}
''');
    await assertHasAssistAt('import ', DartAssistKind.IMPORT_ADD_SHOW, '''
import 'dart:math' show E, PI, max;
main() {
  PI;
  E;
  max(1, 2);
}
''');
  }

  test_importAddShow_OK_onUri() async {
    await resolveTestUnit('''
import 'dart:math';
main() {
  PI;
  E;
  max(1, 2);
}
''');
    await assertHasAssistAt('art:math', DartAssistKind.IMPORT_ADD_SHOW, '''
import 'dart:math' show E, PI, max;
main() {
  PI;
  E;
  max(1, 2);
}
''');
  }

  test_introduceLocalTestedType_BAD_notBlock() async {
    await resolveTestUnit('''
main(p) {
  if (p is String)
    print('not a block');
}
''');
    await assertNoAssistAt('if (p', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE);
  }

  test_introduceLocalTestedType_BAD_notIsExpression() async {
    await resolveTestUnit('''
main(p) {
  if (p == null) {
  }
}
''');
    await assertNoAssistAt('if (p', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE);
  }

  test_introduceLocalTestedType_BAD_notStatement() async {
    await resolveTestUnit('''
class C {
  bool b;
  C(v) : b = v is int;
}''');
    await assertNoAssistAt('is int', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE);
  }

  test_introduceLocalTestedType_OK_if_is() async {
    await resolveTestUnit('''
class MyTypeName {}
main(p) {
  if (p is MyTypeName) {
  }
  p = null;
}
''');
    String expected = '''
class MyTypeName {}
main(p) {
  if (p is MyTypeName) {
    MyTypeName myTypeName = p;
  }
  p = null;
}
''';
    await assertHasAssistAt(
        'is MyType', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
    _assertLinkedGroup(
        change.linkedEditGroups[0],
        ['myTypeName = '],
        expectedSuggestions(LinkedEditSuggestionKind.VARIABLE,
            ['myTypeName', 'typeName', 'name']));
    // another good location
    await assertHasAssistAt(
        'if (p', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
  }

  test_introduceLocalTestedType_OK_if_isNot() async {
    await resolveTestUnit('''
class MyTypeName {}
main(p) {
  if (p is! MyTypeName) {
    return;
  }
}
''');
    String expected = '''
class MyTypeName {}
main(p) {
  if (p is! MyTypeName) {
    return;
  }
  MyTypeName myTypeName = p;
}
''';
    await assertHasAssistAt(
        'is! MyType', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
    _assertLinkedGroup(
        change.linkedEditGroups[0],
        ['myTypeName = '],
        expectedSuggestions(LinkedEditSuggestionKind.VARIABLE,
            ['myTypeName', 'typeName', 'name']));
    // another good location
    await assertHasAssistAt(
        'if (p', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
  }

  test_introduceLocalTestedType_OK_while() async {
    await resolveTestUnit('''
main(p) {
  while (p is String) {
  }
  p = null;
}
''');
    String expected = '''
main(p) {
  while (p is String) {
    String s = p;
  }
  p = null;
}
''';
    await assertHasAssistAt(
        'is String', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
    await assertHasAssistAt(
        'while (p', DartAssistKind.INTRODUCE_LOCAL_CAST_TYPE, expected);
  }

  test_invalidSelection() async {
    await resolveTestUnit('');
    offset = -1;
    length = 0;
    List<Assist> assists = await _computeAssists();
    expect(assists, isEmpty);
  }

  test_invertIfStatement_blocks() async {
    await resolveTestUnit('''
main() {
  if (true) {
    0;
  } else {
    1;
  }
}
''');
    await assertHasAssistAt('if (', DartAssistKind.INVERT_IF_STATEMENT, '''
main() {
  if (false) {
    1;
  } else {
    0;
  }
}
''');
  }

  test_invertIfStatement_statements() async {
    await resolveTestUnit('''
main() {
  if (true)
    0;
  else
    1;
}
''');
    await assertHasAssistAt('if (', DartAssistKind.INVERT_IF_STATEMENT, '''
main() {
  if (false)
    1;
  else
    0;
}
''');
  }

  test_joinIfStatementInner_BAD_innerNotIf() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    print(0);
  }
}
''');
    await assertNoAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_BAD_innerWithElse() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    } else {
      print(1);
    }
  }
}
''');
    await assertNoAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_BAD_statementAfterInner() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(2);
    }
    print(1);
  }
}
''');
    await assertNoAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_BAD_statementBeforeInner() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    print(1);
    if (2 == 2) {
      print(2);
    }
  }
}
''');
    await assertNoAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_BAD_targetNotIf() async {
    await resolveTestUnit('''
main() {
  print(0);
}
''');
    await assertNoAssistAt('print', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_BAD_targetWithElse() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  } else {
    print(1);
  }
}
''');
    await assertNoAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER);
  }

  test_joinIfStatementInner_OK_conditionAndOr() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2 || 3 == 3) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && (2 == 2 || 3 == 3)) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementInner_OK_conditionInvocation() async {
    await resolveTestUnit('''
main() {
  if (isCheck()) {
    if (2 == 2) {
      print(0);
    }
  }
}
bool isCheck() => false;
''');
    await assertHasAssistAt(
        'if (isCheck', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (isCheck() && 2 == 2) {
    print(0);
  }
}
bool isCheck() => false;
''');
  }

  test_joinIfStatementInner_OK_conditionOrAnd() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 || 2 == 2) {
    if (3 == 3) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if ((1 == 1 || 2 == 2) && 3 == 3) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementInner_OK_onCondition() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementInner_OK_simpleConditions_block_block() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementInner_OK_simpleConditions_block_single() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2)
      print(0);
  }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementInner_OK_simpleConditions_single_blockMulti() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(1);
      print(2);
      print(3);
    }
  }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(1);
    print(2);
    print(3);
  }
}
''');
  }

  test_joinIfStatementInner_OK_simpleConditions_single_blockOne() async {
    await resolveTestUnit('''
main() {
  if (1 == 1)
    if (2 == 2) {
      print(0);
    }
}
''');
    await assertHasAssistAt('if (1 ==', DartAssistKind.JOIN_IF_WITH_INNER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_BAD_outerNotIf() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    print(0);
  }
}
''');
    await assertNoAssistAt('if (1 == 1', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_BAD_outerWithElse() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  } else {
    print(1);
  }
}
''');
    await assertNoAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_BAD_statementAfterInner() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(2);
    }
    print(1);
  }
}
''');
    await assertNoAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_BAD_statementBeforeInner() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    print(1);
    if (2 == 2) {
      print(2);
    }
  }
}
''');
    await assertNoAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_BAD_targetNotIf() async {
    await resolveTestUnit('''
main() {
  print(0);
}
''');
    await assertNoAssistAt('print', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_BAD_targetWithElse() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    } else {
      print(1);
    }
  }
}
''');
    await assertNoAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER);
  }

  test_joinIfStatementOuter_OK_conditionAndOr() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2 || 3 == 3) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (2 ==', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && (2 == 2 || 3 == 3)) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_conditionInvocation() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (isCheck()) {
      print(0);
    }
  }
}
bool isCheck() => false;
''');
    await assertHasAssistAt(
        'if (isCheck', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && isCheck()) {
    print(0);
  }
}
bool isCheck() => false;
''');
  }

  test_joinIfStatementOuter_OK_conditionOrAnd() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 || 2 == 2) {
    if (3 == 3) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (3 == 3', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if ((1 == 1 || 2 == 2) && 3 == 3) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_onCondition() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_simpleConditions_block_block() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(0);
    }
  }
}
''');
    await assertHasAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_simpleConditions_block_single() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2)
      print(0);
  }
}
''');
    await assertHasAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_simpleConditions_single_blockMulti() async {
    await resolveTestUnit('''
main() {
  if (1 == 1) {
    if (2 == 2) {
      print(1);
      print(2);
      print(3);
    }
  }
}
''');
    await assertHasAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(1);
    print(2);
    print(3);
  }
}
''');
  }

  test_joinIfStatementOuter_OK_simpleConditions_single_blockOne() async {
    await resolveTestUnit('''
main() {
  if (1 == 1)
    if (2 == 2) {
      print(0);
    }
}
''');
    await assertHasAssistAt('if (2 == 2', DartAssistKind.JOIN_IF_WITH_OUTER, '''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
}
''');
  }

  test_joinVariableDeclaration_onAssignment_BAD_hasInitializer() async {
    await resolveTestUnit('''
main() {
  var v = 1;
  v = 2;
}
''');
    await assertNoAssistAt('v = 2', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notAdjacent() async {
    await resolveTestUnit('''
main() {
  var v;
  var bar;
  v = 1;
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notAssignment() async {
    await resolveTestUnit('''
main() {
  var v;
  v += 1;
}
''');
    await assertNoAssistAt('v += 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notDeclaration() async {
    await resolveTestUnit('''
main(var v) {
  v = 1;
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notLeftArgument() async {
    await resolveTestUnit('''
main() {
  var v;
  1 + v; // marker
}
''');
    await assertNoAssistAt(
        'v; // marker', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notOneVariable() async {
    await resolveTestUnit('''
main() {
  var v, v2;
  v = 1;
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notResolved() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
main() {
  var v;
  x = 1;
}
''');
    await assertNoAssistAt('x = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_BAD_notSameBlock() async {
    await resolveTestUnit('''
main() {
  var v;
  {
    v = 1;
  }
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onAssignment_OK() async {
    await resolveTestUnit('''
main() {
  var v;
  v = 1;
}
''');
    await assertHasAssistAt('v =', DartAssistKind.JOIN_VARIABLE_DECLARATION, '''
main() {
  var v = 1;
}
''');
  }

  test_joinVariableDeclaration_onDeclaration_BAD_hasInitializer() async {
    await resolveTestUnit('''
main() {
  var v = 1;
  v = 2;
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_BAD_lastStatement() async {
    await resolveTestUnit('''
main() {
  if (true)
    var v;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_BAD_nextNotAssignmentExpression() async {
    await resolveTestUnit('''
main() {
  var v;
  42;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_BAD_nextNotExpressionStatement() async {
    await resolveTestUnit('''
main() {
  var v;
  if (true) return;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_BAD_nextNotPureAssignment() async {
    await resolveTestUnit('''
main() {
  var v;
  v += 1;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_BAD_notOneVariable() async {
    await resolveTestUnit('''
main() {
  var v, v2;
  v = 1;
}
''');
    await assertNoAssistAt('v, ', DartAssistKind.JOIN_VARIABLE_DECLARATION);
  }

  test_joinVariableDeclaration_onDeclaration_OK_onName() async {
    await resolveTestUnit('''
main() {
  var v;
  v = 1;
}
''');
    await assertHasAssistAt('v;', DartAssistKind.JOIN_VARIABLE_DECLARATION, '''
main() {
  var v = 1;
}
''');
  }

  test_joinVariableDeclaration_onDeclaration_OK_onType() async {
    await resolveTestUnit('''
main() {
  int v;
  v = 1;
}
''');
    await assertHasAssistAt(
        'int v', DartAssistKind.JOIN_VARIABLE_DECLARATION, '''
main() {
  int v = 1;
}
''');
  }

  test_joinVariableDeclaration_onDeclaration_OK_onVar() async {
    await resolveTestUnit('''
main() {
  var v;
  v = 1;
}
''');
    await assertHasAssistAt(
        'var v', DartAssistKind.JOIN_VARIABLE_DECLARATION, '''
main() {
  var v = 1;
}
''');
  }

  test_removeTypeAnnotation_classField_OK() async {
    await resolveTestUnit('''
class A {
  int v = 1;
}
''');
    await assertHasAssistAt('v = ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
class A {
  var v = 1;
}
''');
  }

  test_removeTypeAnnotation_classField_OK_final() async {
    await resolveTestUnit('''
class A {
  final int v = 1;
}
''');
    await assertHasAssistAt('v = ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
class A {
  final v = 1;
}
''');
  }

  test_removeTypeAnnotation_field_BAD_noInitializer() async {
    await resolveTestUnit('''
class A {
  int v;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.REMOVE_TYPE_ANNOTATION);
  }

  test_removeTypeAnnotation_localVariable_BAD_noInitializer() async {
    await resolveTestUnit('''
main() {
  int v;
}
''');
    await assertNoAssistAt('v;', DartAssistKind.REMOVE_TYPE_ANNOTATION);
  }

  test_removeTypeAnnotation_localVariable_BAD_onInitializer() async {
    await resolveTestUnit('''
main() {
  final int v = 1;
}
''');
    await assertNoAssistAt('1;', DartAssistKind.REMOVE_TYPE_ANNOTATION);
  }

  test_removeTypeAnnotation_localVariable_OK() async {
    await resolveTestUnit('''
main() {
  int a = 1, b = 2;
}
''');
    await assertHasAssistAt('int ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
main() {
  var a = 1, b = 2;
}
''');
  }

  test_removeTypeAnnotation_localVariable_OK_const() async {
    await resolveTestUnit('''
main() {
  const int v = 1;
}
''');
    await assertHasAssistAt('int ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
main() {
  const v = 1;
}
''');
  }

  test_removeTypeAnnotation_localVariable_OK_final() async {
    await resolveTestUnit('''
main() {
  final int v = 1;
}
''');
    await assertHasAssistAt('int ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
main() {
  final v = 1;
}
''');
  }

  test_removeTypeAnnotation_topLevelVariable_BAD_noInitializer() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
int v;
''');
    await assertNoAssistAt('v;', DartAssistKind.REMOVE_TYPE_ANNOTATION);
  }

  test_removeTypeAnnotation_topLevelVariable_BAD_syntheticName() async {
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
MyType
''');
    await assertNoAssistAt('MyType', DartAssistKind.REMOVE_TYPE_ANNOTATION);
  }

  test_removeTypeAnnotation_topLevelVariable_OK() async {
    await resolveTestUnit('''
int V = 1;
''');
    await assertHasAssistAt('int ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
var V = 1;
''');
  }

  test_removeTypeAnnotation_topLevelVariable_OK_final() async {
    await resolveTestUnit('''
final int V = 1;
''');
    await assertHasAssistAt('int ', DartAssistKind.REMOVE_TYPE_ANNOTATION, '''
final V = 1;
''');
  }

  test_replaceConditionalWithIfElse_BAD_noEnclosingStatement() async {
    await resolveTestUnit('''
var v = true ? 111 : 222;
''');
    await assertNoAssistAt(
        '? 111', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE);
  }

  test_replaceConditionalWithIfElse_BAD_notConditional() async {
    await resolveTestUnit('''
main() {
  var v = 42;
}
''');
    await assertNoAssistAt(
        'v = 42', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE);
  }

  test_replaceConditionalWithIfElse_OK_assignment() async {
    await resolveTestUnit('''
main() {
  var v;
  v = true ? 111 : 222;
}
''');
    // on conditional
    await assertHasAssistAt(
        '11 :', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE, '''
main() {
  var v;
  if (true) {
    v = 111;
  } else {
    v = 222;
  }
}
''');
    // on variable
    await assertHasAssistAt(
        'v =', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE, '''
main() {
  var v;
  if (true) {
    v = 111;
  } else {
    v = 222;
  }
}
''');
  }

  test_replaceConditionalWithIfElse_OK_return() async {
    await resolveTestUnit('''
main() {
  return true ? 111 : 222;
}
''');
    await assertHasAssistAt(
        'return ', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE, '''
main() {
  if (true) {
    return 111;
  } else {
    return 222;
  }
}
''');
  }

  test_replaceConditionalWithIfElse_OK_variableDeclaration() async {
    await resolveTestUnit('''
main() {
  int a = 1, vvv = true ? 111 : 222, b = 2;
}
''');
    await assertHasAssistAt(
        '11 :', DartAssistKind.REPLACE_CONDITIONAL_WITH_IF_ELSE, '''
main() {
  int a = 1, vvv, b = 2;
  if (true) {
    vvv = 111;
  } else {
    vvv = 222;
  }
}
''');
  }

  test_replaceIfElseWithConditional_BAD_expressionVsReturn() async {
    await resolveTestUnit('''
main() {
  if (true) {
    print(42);
  } else {
    return;
  }
}
''');
    await assertNoAssistAt(
        'else', DartAssistKind.REPLACE_IF_ELSE_WITH_CONDITIONAL);
  }

  test_replaceIfElseWithConditional_BAD_notIfStatement() async {
    await resolveTestUnit('''
main() {
  print(0);
}
''');
    await assertNoAssistAt(
        'print', DartAssistKind.REPLACE_IF_ELSE_WITH_CONDITIONAL);
  }

  test_replaceIfElseWithConditional_BAD_notSingleStatement() async {
    await resolveTestUnit('''
main() {
  int vvv;
  if (true) {
    print(0);
    vvv = 111;
  } else {
    print(0);
    vvv = 222;
  }
}
''');
    await assertNoAssistAt(
        'if (true)', DartAssistKind.REPLACE_IF_ELSE_WITH_CONDITIONAL);
  }

  test_replaceIfElseWithConditional_OK_assignment() async {
    await resolveTestUnit('''
main() {
  int vvv;
  if (true) {
    vvv = 111;
  } else {
    vvv = 222;
  }
}
''');
    await assertHasAssistAt(
        'if (true)', DartAssistKind.REPLACE_IF_ELSE_WITH_CONDITIONAL, '''
main() {
  int vvv;
  vvv = true ? 111 : 222;
}
''');
  }

  test_replaceIfElseWithConditional_OK_return() async {
    await resolveTestUnit('''
main() {
  if (true) {
    return 111;
  } else {
    return 222;
  }
}
''');
    await assertHasAssistAt(
        'if (true)', DartAssistKind.REPLACE_IF_ELSE_WITH_CONDITIONAL, '''
main() {
  return true ? 111 : 222;
}
''');
  }

  test_splitAndCondition_BAD_hasElse() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 && 2 == 2) {
    print(1);
  } else {
    print(2);
  }
}
''');
    await assertNoAssistAt('&& 2', DartAssistKind.SPLIT_AND_CONDITION);
  }

  test_splitAndCondition_BAD_notAnd() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 || 2 == 2) {
    print(0);
  }
}
''');
    await assertNoAssistAt('|| 2', DartAssistKind.SPLIT_AND_CONDITION);
  }

  test_splitAndCondition_BAD_notPartOfIf() async {
    await resolveTestUnit('''
main() {
  print(1 == 1 && 2 == 2);
}
''');
    await assertNoAssistAt('&& 2', DartAssistKind.SPLIT_AND_CONDITION);
  }

  test_splitAndCondition_BAD_notTopLevelAnd() async {
    await resolveTestUnit('''
main() {
  if (true || (1 == 1 && 2 == 2)) {
    print(0);
  }
  if (true && (3 == 3 && 4 == 4)) {
    print(0);
  }
}
''');
    await assertNoAssistAt('&& 2', DartAssistKind.SPLIT_AND_CONDITION);
    await assertNoAssistAt('&& 4', DartAssistKind.SPLIT_AND_CONDITION);
  }

  test_splitAndCondition_OK_innerAndExpression() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 && 2 == 2 && 3 == 3) {
    print(0);
  }
}
''');
    await assertHasAssistAt('&& 2 == 2', DartAssistKind.SPLIT_AND_CONDITION, '''
main() {
  if (1 == 1) {
    if (2 == 2 && 3 == 3) {
      print(0);
    }
  }
}
''');
  }

  test_splitAndCondition_OK_thenBlock() async {
    await resolveTestUnit('''
main() {
  if (true && false) {
    print(0);
    if (3 == 3) {
      print(1);
    }
  }
}
''');
    await assertHasAssistAt('&& false', DartAssistKind.SPLIT_AND_CONDITION, '''
main() {
  if (true) {
    if (false) {
      print(0);
      if (3 == 3) {
        print(1);
      }
    }
  }
}
''');
  }

  test_splitAndCondition_OK_thenStatement() async {
    await resolveTestUnit('''
main() {
  if (true && false)
    print(0);
}
''');
    await assertHasAssistAt('&& false', DartAssistKind.SPLIT_AND_CONDITION, '''
main() {
  if (true)
    if (false)
      print(0);
}
''');
  }

  test_splitAndCondition_wrong() async {
    await resolveTestUnit('''
main() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
  print(3 == 3 && 4 == 4);
}
''');
    // not binary expression
    await assertNoAssistAt('main() {', DartAssistKind.SPLIT_AND_CONDITION);
    // selection is not empty and includes more than just operator
    {
      length = 5;
      await assertNoAssistAt('&& 2 == 2', DartAssistKind.SPLIT_AND_CONDITION);
    }
  }

  test_splitVariableDeclaration_BAD_notOneVariable() async {
    await resolveTestUnit('''
main() {
  var v = 1, v2;
}
''');
    await assertNoAssistAt('v = 1', DartAssistKind.SPLIT_VARIABLE_DECLARATION);
  }

  test_splitVariableDeclaration_OK_onName() async {
    await resolveTestUnit('''
main() {
  var v = 1;
}
''');
    await assertHasAssistAt(
        'v =', DartAssistKind.SPLIT_VARIABLE_DECLARATION, '''
main() {
  var v;
  v = 1;
}
''');
  }

  test_splitVariableDeclaration_OK_onType() async {
    await resolveTestUnit('''
main() {
  int v = 1;
}
''');
    await assertHasAssistAt(
        'int ', DartAssistKind.SPLIT_VARIABLE_DECLARATION, '''
main() {
  int v;
  v = 1;
}
''');
  }

  test_splitVariableDeclaration_OK_onVar() async {
    await resolveTestUnit('''
main() {
  var v = 1;
}
''');
    await assertHasAssistAt(
        'var ', DartAssistKind.SPLIT_VARIABLE_DECLARATION, '''
main() {
  var v;
  v = 1;
}
''');
  }

  test_surroundWith_block() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_BLOCK, '''
main() {
// start
  {
    print(0);
    print(1);
  }
// end
}
''');
  }

  test_surroundWith_doWhile() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_DO_WHILE, '''
main() {
// start
  do {
    print(0);
    print(1);
  } while (condition);
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['condition);']);
    _assertExitPosition(after: 'condition);');
  }

  test_surroundWith_for() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_FOR, '''
main() {
// start
  for (var v = init; condition; increment) {
    print(0);
    print(1);
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['v =']);
    _assertLinkedGroup(change.linkedEditGroups[1], ['init;']);
    _assertLinkedGroup(change.linkedEditGroups[2], ['condition;']);
    _assertLinkedGroup(change.linkedEditGroups[3], ['increment']);
    _assertExitPosition(after: '  }');
  }

  test_surroundWith_forIn() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_FOR_IN, '''
main() {
// start
  for (var item in iterable) {
    print(0);
    print(1);
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['item']);
    _assertLinkedGroup(change.linkedEditGroups[1], ['iterable']);
    _assertExitPosition(after: '  }');
  }

  test_surroundWith_if() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_IF, '''
main() {
// start
  if (condition) {
    print(0);
    print(1);
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['condition']);
    _assertExitPosition(after: '  }');
  }

  test_surroundWith_tryCatch() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_TRY_CATCH, '''
main() {
// start
  try {
    print(0);
    print(1);
  } on Exception catch (e) {
    // TODO
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['Exception']);
    _assertLinkedGroup(change.linkedEditGroups[1], ['e) {']);
    _assertLinkedGroup(change.linkedEditGroups[2], ['// TODO']);
    _assertExitPosition(after: '// TODO');
  }

  test_surroundWith_tryFinally() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_TRY_FINALLY, '''
main() {
// start
  try {
    print(0);
    print(1);
  } finally {
    // TODO
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['// TODO']);
    _assertExitPosition(after: '// TODO');
  }

  test_surroundWith_while() async {
    await resolveTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _setStartEndSelection();
    await assertHasAssist(DartAssistKind.SURROUND_WITH_WHILE, '''
main() {
// start
  while (condition) {
    print(0);
    print(1);
  }
// end
}
''');
    _assertLinkedGroup(change.linkedEditGroups[0], ['condition']);
    _assertExitPosition(after: '  }');
  }

  void _assertExitPosition({String before, String after}) {
    Position exitPosition = change.selection;
    expect(exitPosition, isNotNull);
    expect(exitPosition.file, testFile);
    if (before != null) {
      expect(exitPosition.offset, resultCode.indexOf(before));
    } else if (after != null) {
      expect(exitPosition.offset, resultCode.indexOf(after) + after.length);
    } else {
      fail("One of 'before' or 'after' expected.");
    }
  }

  /**
   * Computes assists and verifies that there is an assist of the given kind.
   */
  Future<Assist> _assertHasAssist(AssistKind kind) async {
    List<Assist> assists = await _computeAssists();
    for (Assist assist in assists) {
      if (assist.kind == kind) {
        return assist;
      }
    }
    fail('Expected to find assist $kind in\n${assists.join('\n')}');
  }

  void _assertLinkedGroup(LinkedEditGroup group, List<String> expectedStrings,
      [List<LinkedEditSuggestion> expectedSuggestions]) {
    List<Position> expectedPositions = _findResultPositions(expectedStrings);
    expect(group.positions, unorderedEquals(expectedPositions));
    if (expectedSuggestions != null) {
      expect(group.suggestions, unorderedEquals(expectedSuggestions));
    }
  }

  Future<List<Assist>> _computeAssists() async {
    CompilationUnitElement testUnitElement =
        resolutionMap.elementDeclaredByCompilationUnit(testUnit);
    DartAssistContext assistContext;
    assistContext = new _DartAssistContextForValues(
        testUnitElement.source, offset, length, driver, testUnit);
    AssistProcessor processor = new AssistProcessor(assistContext);
    return await processor.compute();
  }

  List<Position> _findResultPositions(List<String> searchStrings) {
    List<Position> positions = <Position>[];
    for (String search in searchStrings) {
      int offset = resultCode.indexOf(search);
      positions.add(new Position(testFile, offset));
    }
    return positions;
  }

  void _setCaretLocation() {
    offset = findOffset('/*caret*/') + '/*caret*/'.length;
    length = 0;
  }

  void _setStartEndSelection() {
    offset = findOffset('// start\n') + '// start\n'.length;
    length = findOffset('// end') - offset;
  }
}

@reflectiveTest
class AssistProcessorTest_UseCFE extends AssistProcessorTest {
  @override
  bool get useCFE => true;

  // Many of these tests are failing because the CFE is not able to find the
  // flutter package. It seems likely that there is a problem with the way the
  // tests (or some underlying layer) is passing package resolution to the CFE.

  @failingTest
  @override
  test_addTypeAnnotation_parameter_BAD_hasExplicitType() =>
      super.test_addTypeAnnotation_parameter_BAD_hasExplicitType();

  @failingTest
  @override
  test_addTypeAnnotation_parameter_BAD_noPropagatedType() =>
      super.test_addTypeAnnotation_parameter_BAD_noPropagatedType();

  @failingTest
  @override
  test_addTypeAnnotation_parameter_OK() =>
      super.test_addTypeAnnotation_parameter_OK();

  @failingTest
  @override
  test_convertToFinalField_OK_hasOverride() =>
      super.test_convertToFinalField_OK_hasOverride();

  @failingTest
  @override
  test_convertToFunctionSyntax_BAD_functionTypedParameter_insideParameterList() =>
      super
          .test_convertToFunctionSyntax_BAD_functionTypedParameter_insideParameterList();

  @failingTest
  @override
  test_convertToFunctionSyntax_BAD_functionTypedParameter_noParameterTypes() =>
      super
          .test_convertToFunctionSyntax_BAD_functionTypedParameter_noParameterTypes();

  @failingTest
  @override
  test_convertToFunctionSyntax_OK_functionTypedParameter_noReturnType_noTypeParameters() =>
      super
          .test_convertToFunctionSyntax_OK_functionTypedParameter_noReturnType_noTypeParameters();

  @failingTest
  @override
  test_convertToFunctionSyntax_OK_functionTypedParameter_returnType() =>
      super.test_convertToFunctionSyntax_OK_functionTypedParameter_returnType();

  @failingTest
  @override
  test_convertToGetter_OK() => super.test_convertToGetter_OK();

  @failingTest
  @override
  test_flutterConvertToChildren_BAD_childUnresolved() =>
      super.test_flutterConvertToChildren_BAD_childUnresolved();

  @failingTest
  @override
  test_flutterConvertToChildren_BAD_notOnChild() =>
      super.test_flutterConvertToChildren_BAD_notOnChild();

  @failingTest
  @override
  test_flutterConvertToChildren_OK_multiLine() =>
      super.test_flutterConvertToChildren_OK_multiLine();

  @failingTest
  @override
  test_flutterConvertToChildren_OK_newlineChild() =>
      super.test_flutterConvertToChildren_OK_newlineChild();

  @failingTest
  @override
  test_flutterConvertToChildren_OK_singleLine() =>
      super.test_flutterConvertToChildren_OK_singleLine();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_BAD_notClass() =>
      super.test_flutterConvertToStatefulWidget_BAD_notClass();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_BAD_notStatelessWidget() =>
      super.test_flutterConvertToStatefulWidget_BAD_notStatelessWidget();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_BAD_notWidget() =>
      super.test_flutterConvertToStatefulWidget_BAD_notWidget();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK() =>
      super.test_flutterConvertToStatefulWidget_OK();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK_empty() =>
      super.test_flutterConvertToStatefulWidget_OK_empty();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK_fields() =>
      super.test_flutterConvertToStatefulWidget_OK_fields();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK_getters() =>
      super.test_flutterConvertToStatefulWidget_OK_getters();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK_methods() =>
      super.test_flutterConvertToStatefulWidget_OK_methods();

  @failingTest
  @override
  test_flutterConvertToStatefulWidget_OK_tail() =>
      super.test_flutterConvertToStatefulWidget_OK_tail();

  @failingTest
  @override
  test_flutterMoveWidgetDown_BAD_last() =>
      super.test_flutterMoveWidgetDown_BAD_last();

  @failingTest
  @override
  test_flutterMoveWidgetDown_BAD_notInList() =>
      super.test_flutterMoveWidgetDown_BAD_notInList();

  @failingTest
  @override
  test_flutterMoveWidgetDown_OK() => super.test_flutterMoveWidgetDown_OK();

  @failingTest
  @override
  test_flutterMoveWidgetUp_BAD_first() =>
      super.test_flutterMoveWidgetUp_BAD_first();

  @failingTest
  @override
  test_flutterMoveWidgetUp_BAD_notInList() =>
      super.test_flutterMoveWidgetUp_BAD_notInList();

  @failingTest
  @override
  test_flutterMoveWidgetUp_OK() => super.test_flutterMoveWidgetUp_OK();

  @failingTest
  @override
  test_flutterRemoveWidget_BAD_childrenMultipleIntoChild() =>
      super.test_flutterRemoveWidget_BAD_childrenMultipleIntoChild();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_childIntoChild_multiLine() =>
      super.test_flutterRemoveWidget_OK_childIntoChild_multiLine();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_childIntoChild_singleLine() =>
      super.test_flutterRemoveWidget_OK_childIntoChild_singleLine();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_childIntoChildren() =>
      super.test_flutterRemoveWidget_OK_childIntoChildren();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_childrenOneIntoChild() =>
      super.test_flutterRemoveWidget_OK_childrenOneIntoChild();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_childrenOneIntoReturn() =>
      super.test_flutterRemoveWidget_OK_childrenOneIntoReturn();

  @failingTest
  @override
  test_flutterRemoveWidget_OK_intoChildren() =>
      super.test_flutterRemoveWidget_OK_intoChildren();

  @failingTest
  @override
  test_flutterSwapWithChild_OK() => super.test_flutterSwapWithChild_OK();

  @failingTest
  @override
  test_flutterSwapWithChild_OK_notFormatted() =>
      super.test_flutterSwapWithChild_OK_notFormatted();

  @failingTest
  @override
  test_flutterSwapWithParent_OK() => super.test_flutterSwapWithParent_OK();

  @failingTest
  @override
  test_flutterSwapWithParent_OK_notFormatted() =>
      super.test_flutterSwapWithParent_OK_notFormatted();

  @failingTest
  @override
  test_flutterSwapWithParent_OK_outerIsInChildren() =>
      super.test_flutterSwapWithParent_OK_outerIsInChildren();

  @failingTest
  @override
  test_flutterWrapCenter_BAD_onCenter() =>
      super.test_flutterWrapCenter_BAD_onCenter();

  @failingTest
  @override
  test_flutterWrapCenter_OK() => super.test_flutterWrapCenter_OK();

  @failingTest
  @override
  test_flutterWrapCenter_OK_implicitNew() =>
      super.test_flutterWrapCenter_OK_implicitNew();

  @failingTest
  @override
  test_flutterWrapCenter_OK_namedConstructor() =>
      super.test_flutterWrapCenter_OK_namedConstructor();

  @failingTest
  @override
  test_flutterWrapColumn_OK_coveredByWidget() =>
      super.test_flutterWrapColumn_OK_coveredByWidget();

  @failingTest
  @override
  test_flutterWrapColumn_OK_coversWidgets() =>
      super.test_flutterWrapColumn_OK_coversWidgets();

  @failingTest
  @override
  test_flutterWrapColumn_OK_implicitNew() =>
      super.test_flutterWrapColumn_OK_implicitNew();

  @failingTest
  @override
  test_flutterWrapPadding_BAD_onPadding() =>
      super.test_flutterWrapPadding_BAD_onPadding();

  @failingTest
  @override
  test_flutterWrapPadding_OK() => super.test_flutterWrapPadding_OK();

  @failingTest
  @override
  test_flutterWrapRow_OK() => super.test_flutterWrapRow_OK();

  @failingTest
  @override
  test_flutterWrapWidget_BAD_multiLine() =>
      super.test_flutterWrapWidget_BAD_multiLine();

  @failingTest
  @override
  test_flutterWrapWidget_BAD_singleLine() =>
      super.test_flutterWrapWidget_BAD_singleLine();

  @failingTest
  @override
  test_flutterWrapWidget_OK_multiLine() =>
      super.test_flutterWrapWidget_OK_multiLine();

  @failingTest
  @override
  test_flutterWrapWidget_OK_multiLines() =>
      super.test_flutterWrapWidget_OK_multiLines();

  @failingTest
  @override
  test_flutterWrapWidget_OK_multiLines_eol2() =>
      super.test_flutterWrapWidget_OK_multiLines_eol2();

  @failingTest
  @override
  test_flutterWrapWidget_OK_singleLine1() =>
      super.test_flutterWrapWidget_OK_singleLine1();

  @failingTest
  @override
  test_flutterWrapWidget_OK_singleLine2() =>
      super.test_flutterWrapWidget_OK_singleLine2();

  @failingTest
  @override
  test_flutterWrapWidget_OK_variable() =>
      super.test_flutterWrapWidget_OK_variable();

  @failingTest
  @override
  test_importAddShow_BAD_unresolvedUri() =>
      super.test_importAddShow_BAD_unresolvedUri();

  @failingTest
  @override
  test_removeTypeAnnotation_topLevelVariable_BAD_syntheticName() =>
      super.test_removeTypeAnnotation_topLevelVariable_BAD_syntheticName();
}

class _DartAssistContextForValues implements DartAssistContext {
  @override
  final Source source;

  @override
  final int selectionOffset;

  @override
  final int selectionLength;

  @override
  final AnalysisDriver analysisDriver;

  @override
  final CompilationUnit unit;

  _DartAssistContextForValues(this.source, this.selectionOffset,
      this.selectionLength, this.analysisDriver, this.unit);
}
