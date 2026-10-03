// SA-INT-001: client mirror of the products table rules (RULE-PRD-01..03).
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/validation/product_rules.dart';

void main() {
  group('ProductRules.normalizeCode (trim, drop spaces, uppercase, add #)', () {
    test("'101' becomes '#101'", () {
      expect(ProductRules.normalizeCode('101'), '#101');
    });

    test('lower case, inner and outer spaces are normalised', () {
      expect(ProductRules.normalizeCode(' a 01 '), '#A01');
      expect(ProductRules.normalizeCode('#b2'), '#B2');
      expect(ProductRules.normalizeCode('# sr 7'), '#SR7');
    });

    test('empty input stays empty so it can be reported as missing', () {
      expect(ProductRules.normalizeCode('   '), '');
    });
  });

  group('ProductRules.validateCode mirrors CHECK (code ~ ^#[A-Z0-9]{1,6}\$)', () {
    test("'101' is accepted (normalised to '#101')", () {
      expect(ProductRules.validateCode('101'), isNull);
      expect(ProductRules.isValidCode(ProductRules.normalizeCode('101')), isTrue);
    });

    test("'saree01' is rejected (7 characters after #)", () {
      expect(ProductRules.normalizeCode('saree01'), '#SAREE01');
      expect(ProductRules.validateCode('saree01'), contains('at most 6'));
    });

    test('7 or more characters are rejected, 6 are accepted', () {
      expect(ProductRules.validateCode('#ABCDEFG'), isNotNull);
      expect(ProductRules.validateCode('#ABCDEFGH'), isNotNull);
      expect(ProductRules.validateCode('#ABCDEF'), isNull);
    });

    test('symbols, an empty body and an empty code are rejected', () {
      expect(ProductRules.validateCode('A-07'), contains('letters A–Z and digits 0–9'));
      expect(ProductRules.validateCode('#'), isNotNull);
      expect(ProductRules.validateCode(''), isNotNull);
      expect(ProductRules.validateCode('##A01'), isNotNull);
    });

    test('client verdict equals the database regex for every normalised code', () {
      final dbCheck = RegExp(r'^#[A-Z0-9]{1,6}$');
      const samples = [
        '101', 'a01', '#A01', 'A05', '#SAREE01', 'saree1', '#A-07', '#', '', 'zz 99', '#abcdef', '#ABCDEFG', 'é1',
      ];
      for (final raw in samples) {
        final normalised = ProductRules.normalizeCode(raw);
        expect(
          ProductRules.validateCode(raw) == null,
          dbCheck.hasMatch(normalised),
          reason: 'raw="$raw" normalised="$normalised"',
        );
      }
    });

    test('duplicate codes inside the drop are reported (RULE-PRD-02)', () {
      expect(ProductRules.validateCodeUnique('a01', ['#A01', '#A02']), contains('already used'));
      expect(ProductRules.validateCodeUnique('#A03', ['#A01', '#A02']), isNull);
    });
  });

  group('ProductRules title / size / price', () {
    test('title longer than 100 characters is rejected; 100 is accepted; empty is optional', () {
      expect(ProductRules.validateTitle('x' * 101), contains('at most 100'));
      expect(ProductRules.validateTitle('x' * 100), isNull);
      expect(ProductRules.validateTitle('   '), isNull);
      expect(ProductRules.validateTitle('', required: true), isNotNull);
    });

    test('size longer than 30 characters is rejected', () {
      expect(ProductRules.validateSize('s' * 31), contains('at most 30'));
      expect(ProductRules.validateSize('Free Size'), isNull);
    });

    test('price must be a positive integer number of paisa that fits an INT', () {
      expect(ProductRules.validatePricePaisa(0), isNotNull);
      expect(ProductRules.validatePricePaisa(-100), isNotNull);
      expect(ProductRules.validatePricePaisa(null), isNotNull);
      expect(ProductRules.validatePricePaisa(150000), isNull);
      expect(ProductRules.validatePricePaisa(ProductRules.maxPricePaisa + 1), isNotNull);
    });

    test('rupee input is parsed to integer paisa', () {
      expect(ProductRules.parseRupeesToPaisa('1500'), 150000);
      expect(ProductRules.parseRupeesToPaisa('1,500'), 150000);
      expect(ProductRules.parseRupeesToPaisa('0'), isNull);
      expect(ProductRules.parseRupeesToPaisa('12.50'), isNull);
      expect(ProductRules.parseRupeesToPaisa('abc'), isNull);
      expect(ProductRules.parseRupeesToPaisa('99999999'), isNull); // > INT range in paisa
      expect(ProductRules.validatePriceRupees(''), isNotNull);
      expect(ProductRules.validatePriceRupees('0'), contains('above ₹0'));
      expect(ProductRules.validatePriceRupees('1500'), isNull);
    });

    test('validatePiece reports every invalid field', () {
      final errors = ProductRules.validatePiece(
        code: 'saree01',
        title: 'x' * 101,
        size: 's' * 31,
        pricePaisa: 0,
      );
      expect(errors.keys, containsAll(<String>['code', 'title', 'size', 'price']));
      expect(
        ProductRules.validatePiece(code: '101', title: 'Kantha Saree', size: 'Free Size', pricePaisa: 150000),
        isEmpty,
      );
    });
  });
}
