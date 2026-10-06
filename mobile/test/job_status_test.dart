import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/job_status.dart';

Map<String, dynamic> job(String status, {String? paidAt}) => {
      'status': status,
      'paymentReleasedAt': ?paidAt,
    };

void main() {
  group('isActiveForGiver', () {
    test('every stage before completion stays on the home screen', () {
      // 'reached' in particular: a job used to vanish the moment the
      // worker marked they had arrived.
      expect(isActiveForGiver(job('open')), isTrue);
      expect(isActiveForGiver(job('confirmed')), isTrue);
      expect(isActiveForGiver(job('reached')), isTrue);
      expect(isActiveForGiver(job('in_progress')), isTrue);
    });

    test('a completed job stays until the payment is released', () {
      // The reported case: work done, money still owed.
      expect(isActiveForGiver(job('completed')), isTrue);
      expect(isActiveForGiver(job('completed', paidAt: '')), isTrue);
    });

    test('a completed AND paid job drops off', () {
      expect(
        isActiveForGiver(job('completed', paidAt: '2026-09-09T10:00:00.000Z')),
        isFalse,
      );
    });

    test('cancelled never shows, paid or not', () {
      expect(isActiveForGiver(job('cancelled')), isFalse);
      expect(
        isActiveForGiver(job('cancelled', paidAt: '2026-09-09T10:00:00.000Z')),
        isFalse,
      );
    });

    test('disputed is excluded so it cannot linger forever', () {
      // Resolving a dispute never stamps paymentReleasedAt, so treating
      // "unpaid" as "active" would pin a disputed job here permanently.
      expect(isActiveForGiver(job('disputed')), isFalse);
    });

    test('an unknown or missing status is not active', () {
      expect(isActiveForGiver(job('')), isFalse);
      expect(isActiveForGiver(<String, dynamic>{}), isFalse);
      expect(isActiveForGiver(job('something_new')), isFalse);
    });
  });

  group('isPaymentSettled', () {
    test('reads the settle stamp, tolerating blanks', () {
      expect(isPaymentSettled(job('completed')), isFalse);
      expect(isPaymentSettled(job('completed', paidAt: '')), isFalse);
      expect(isPaymentSettled(job('completed', paidAt: '   ')), isFalse);
      expect(
        isPaymentSettled(job('completed', paidAt: '2026-09-09T10:00:00.000Z')),
        isTrue,
      );
    });
  });

  group('isActiveForWorker', () {
    const me = 'worker-1';
    Map<String, dynamic> assigned(String status, {String to = me, String? paidAt}) => {
          'status': status,
          'selectedJobtaker': to,
          'paymentReleasedAt': ?paidAt,
        };

    test('shows work this user was actually selected for', () {
      expect(isActiveForWorker(assigned('confirmed'), me), isTrue);
      expect(isActiveForWorker(assigned('reached'), me), isTrue);
      expect(isActiveForWorker(assigned('in_progress'), me), isTrue);
    });

    test('a completed job stays until the worker is paid', () {
      expect(isActiveForWorker(assigned('completed'), me), isTrue);
      expect(
        isActiveForWorker(
          assigned('completed', paidAt: '2026-09-10T09:00:00.000Z'),
          me,
        ),
        isFalse,
      );
    });

    test('merely applying is not being on the job', () {
      // /jobs/applied/me returns jobs this user only showed interest in.
      // Someone else was hired here, so it is not their current work.
      expect(isActiveForWorker(assigned('in_progress', to: 'worker-2'), me),
          isFalse);
      expect(isActiveForWorker({'status': 'open'}, me), isFalse);
    });

    test('accepts a populated jobtaker object, not just an id', () {
      final job = {
        'status': 'in_progress',
        'selectedJobtaker': {'_id': me, 'name': 'Suresh'},
      };
      expect(isActiveForWorker(job, me), isTrue);
    });

    test('no signed-in user means nothing is active', () {
      expect(isActiveForWorker(assigned('in_progress'), null), isFalse);
      expect(isActiveForWorker(assigned('in_progress'), ''), isFalse);
    });
  });

  group('workerStatusLabel', () {
    test("describes each stage in the worker's terms", () {
      expect(workerStatusLabel({'status': 'confirmed'}),
          'Accepted — head to the location');
      expect(workerStatusLabel({'status': 'reached'}), 'You have arrived');
      expect(workerStatusLabel({'status': 'in_progress'}), 'Work in progress');
    });

    test('distinguishes paid from awaiting payment', () {
      expect(workerStatusLabel({'status': 'completed'}), 'Awaiting payment');
      expect(
        workerStatusLabel({
          'status': 'completed',
          'paymentReleasedAt': '2026-09-10T09:00:00.000Z',
        }),
        'Paid',
      );
    });
  });
}
