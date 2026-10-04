// Tests for the approvals queue.

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_desktop_companion/app/approvals.dart';

void main() {
  group('ApprovalQueue.requiresApproval', () {
    test('gates device.* commands', () {
      expect(ApprovalQueue.requiresApproval('device.health'), isTrue);
      expect(ApprovalQueue.requiresApproval('device.invoke'), isTrue);
    });

    test('gates display.draw_url', () {
      expect(ApprovalQueue.requiresApproval('display.draw_url'), isTrue);
    });

    test('lets benign commands through', () {
      expect(
        ApprovalQueue.requiresApproval('companion.set_status'),
        isFalse,
      );
      expect(
        ApprovalQueue.requiresApproval('display.show_animation'),
        isFalse,
      );
      expect(
        ApprovalQueue.requiresApproval('companion.set_display'),
        isFalse,
      );
    });
  });

  group('ApprovalQueue flow', () {
    test('approve resolves the request with true', () async {
      final queue = ApprovalQueue();
      final future = queue.request('device.health', const {});
      expect(queue.pendingCount, 1);
      queue.approve(queue.pending.single.id);
      expect(await future, isTrue);
      expect(queue.pendingCount, 0);
      queue.close();
    });

    test('deny resolves the request with false', () async {
      final queue = ApprovalQueue();
      final future = queue.request('display.draw_url', const {
        'url': 'https://example.com/x.png',
      });
      queue.deny(queue.pending.single.id);
      expect(await future, isFalse);
      expect(queue.pendingCount, 0);
      queue.close();
    });

    test('denyAll clears everything as denied', () async {
      final queue = ApprovalQueue();
      final first = queue.request('device.health', const {});
      final second = queue.request('device.health', const {});
      expect(queue.pendingCount, 2);
      queue.denyAll();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(queue.pendingCount, 0);
      queue.close();
    });

    test('deciding an unknown id is a no-op', () async {
      final queue = ApprovalQueue();
      final future = queue.request('device.health', const {});
      queue.approve('nope');
      queue.deny('nope');
      expect(queue.pendingCount, 1);
      queue.approve(queue.pending.single.id);
      expect(await future, isTrue);
      queue.close();
    });

    test('params are preserved on the pending approval', () async {
      final queue = ApprovalQueue();
      final future = queue.request('display.draw_url', const {
        'url': 'https://example.com/x.png',
      });
      final pending = queue.pending.single;
      expect(pending.command, 'display.draw_url');
      expect(pending.params['url'], 'https://example.com/x.png');
      queue.deny(pending.id);
      await future;
      queue.close();
    });
  });
}
