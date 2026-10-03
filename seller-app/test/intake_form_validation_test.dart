// SA-INT-001: the camera intake form validates code / title / price inline and
// its Form refuses to save invalid input (the sheet only enqueues when
// Form.validate() passes).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/validation/product_rules.dart';
import 'package:seller_app/presentation/intake/intake_draft_fields.dart';

import 'support/p0_fakes.dart';

class _Harness {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController(text: '#A02');
  final title = TextEditingController();
  final price = TextEditingController(text: '1500');

  Widget build() => testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: IntakeDraftFields(
                codeController: code,
                titleController: title,
                priceController: price,
                existingCodes: () => const ['#A01'],
              ),
            ),
          ),
        ),
      );

  void dispose() {
    code.dispose();
    title.dispose();
    price.dispose();
  }
}

void main() {
  testWidgets('invalid codes show an inline reason and block saving', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.build());

    await tester.enterText(find.byKey(const ValueKey('intake-code-field')), 'saree01');
    await tester.pump();
    expect(find.textContaining('at most 6 letters/digits after #'), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byKey(const ValueKey('intake-code-field')), 'A-07');
    await tester.pump();
    expect(find.textContaining('only letters A–Z and digits 0–9'), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byKey(const ValueKey('intake-code-field')), 'a01');
    await tester.pump();
    expect(find.text('Code #A01 is already used in this drop. Choose another code.'), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byKey(const ValueKey('intake-code-field')), '101');
    await tester.pump();
    expect(h.formKey.currentState!.validate(), isTrue);
    expect(ProductRules.normalizeCode(h.code.text), '#101'); // what the sheet enqueues
  });

  testWidgets('a title over 100 characters and a zero price are refused', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.build());

    await tester.enterText(find.byKey(const ValueKey('intake-title-field')), 'x' * 101);
    await tester.pump();
    expect(find.textContaining('Title can be at most 100 characters'), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byKey(const ValueKey('intake-title-field')), 'Kantha Stitch Saree');
    await tester.enterText(find.byKey(const ValueKey('intake-price-field')), '0');
    await tester.pump();
    expect(find.text('Enter a price above ₹0.'), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byKey(const ValueKey('intake-price-field')), '1500');
    await tester.pump();
    expect(h.formKey.currentState!.validate(), isTrue);
    expect(ProductRules.parseRupeesToPaisa(h.price.text), 150000);
  });
}
