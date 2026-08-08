// Matching a UPI payee against the address book, which is what silently
// relabels a payment as "Personal".
//
// The risk here is asymmetric. A miss is a small annoyance — the payment sits
// unlabeled until the user names it. A FALSE match is worse: money quietly
// files itself under a friend's name, the category is wrong, and nothing ever
// flags it. So most of these tests are about what must NOT match.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/contacts_service.dart';

void main() {
  final contacts = ContactsService.instance;

  String? match(List<String> book, String payee) {
    contacts.loadNamesForTest(book);
    return contacts.matchContactName(payee);
  }

  group('matches a real person', () {
    test('exact name', () {
      expect(match(['Mohit Sharma'], 'Mohit Sharma'), 'Mohit Sharma');
    });

    test('ignores case and spacing from the bank', () {
      expect(match(['Mohit Sharma'], 'MOHIT   SHARMA'), 'Mohit Sharma');
    });

    test('order does not matter — banks reorder names', () {
      expect(match(['Mohit Sharma'], 'Sharma Mohit'), 'Mohit Sharma');
    });

    test('survives a name the bank truncated', () {
      // The real case this rule exists for: the bank cuts the surname short.
      expect(match(['Adil Deokar'], 'Adil Rahul Deok'), 'Adil Deokar');
    });

    test('tolerates an extra middle name', () {
      expect(match(['Pranav Kulkarni'], 'Pranav Ramesh Kulkarni'),
          'Pranav Kulkarni');
    });

    test('returns the CONTACT spelling, not the bank spelling', () {
      // The point of the feature: show the name you know them by.
      expect(match(['Adil Deokar'], 'ADIL RAHUL DEOK'), 'Adil Deokar');
    });
  });

  group('must not match — a merchant is not a friend', () {
    test('a shop with one name in common stays unmatched', () {
      // "Ganpati" alone must not turn a grocery run into a payment to a person.
      expect(match(['Ganpati Sharma'], 'SHREE GANPATI STORES'), isNull);
    });

    test('a single shared first name is not enough for a 2-token contact', () {
      expect(match(['Mohit Sharma'], 'Mohit Enterprises'), isNull);
    });

    test('unrelated merchants never match', () {
      final book = ['Mohit Sharma', 'Adil Deokar', 'Pranav Kulkarni'];
      for (final merchant in [
        'ZOMATO',
        'Blinkit',
        'SOUTH SPICE CAFE',
        'HARDCASTLE RESTA',
        'ATM Withdrawal',
      ]) {
        expect(match(book, merchant), isNull, reason: '$merchant is a merchant');
      }
    });

    test('short tokens cannot carry a match on their own', () {
      // Initials and 3-letter fragments are far too weak to relabel money.
      expect(match(['Raj Kumar'], 'RAJ TRADERS'), isNull);
    });
  });

  group('degrades safely', () {
    test('an empty address book matches nothing', () {
      contacts.loadNamesForTest([]);
      expect(contacts.matchContactName('Mohit Sharma'), isNull);
    });

    test('an empty or null payee never matches', () {
      expect(match(['Mohit Sharma'], ''), isNull);
      contacts.loadNamesForTest(['Mohit Sharma']);
      expect(contacts.matchContactName(null), isNull);
    });

    test('a payee of only punctuation or digits never matches', () {
      expect(match(['Mohit Sharma'], '9876543210'), isNull);
      expect(match(['Mohit Sharma'], '--- ---'), isNull);
    });

    test('contacts with no usable name are skipped, not crashed on', () {
      expect(match(['', '  ', '42', 'Mohit Sharma'], 'Mohit Sharma'),
          'Mohit Sharma');
    });
  });
}
