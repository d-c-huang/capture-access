Capture Access for macOS �� v0.2.0
=================================

����
- ʹ�� macOS �Դ�����ѡ����ѡ�񵥸����ڲ���ͼ��
- Ԥ�����ٴν�ͼ������ PNG������ͼƬ��
- Retina ���سߴ磻���󴰿ڵȱ���С�����Ƶ���ͼ����ڴ濪����
- ����ȡ��ѡ�񡢽�ͼ��ʱ��ϵͳ��Ȩ�ʹ���ʧЧ��
- ���ö�����ʾӦ�ã����л���ʽ NSWindow.sharingType ������
- ��¼����Ƶ�����Զ�����ͼƬ�����ϴ��������ݡ�

ϵͳҪ��
macOS 14 Sonoma ����°汾��Intel x86_64 / Apple Silicon arm64��
������Ҫ Xcode 15+ ��� macOS 14+ SDK �� Command Line Tools���Լ� Swift 5.9+��
������Ϊϵͳ��ܣ������������� Swift ����

����������
����Ŀ��Ŀ¼ִ�У�
  bash macos/build.sh
�ű�Ĭ�Ϲ�����ǰ Mac �ܹ����� macos/dist �����ɣ�
  CaptureAccess.app
  CaptureAccess-macOS-<�ܹ�>.zip
��ʾӦ�������� CaptureAccess.app/Contents/Resources/CaptureAccessDemo.app��
˫�� CaptureAccess.app ��������ִ�У�
  open macos/dist/CaptureAccess.app

ͨ�ö�����
  bash macos/build.sh --arch universal
Ҳ֧�� --arch arm64 �� --arch x86_64��

ǩ��
Ĭ��ʹ�ñ��� ad-hoc ǩ�������迪�����˻����ⲻ���� Apple ��֤��
��ʽ�ַ�ʱ��ʹ���Լ��� Developer ID ǩ�������й�֤��
�����ṩ����ǩ�����ݣ�
  SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash macos/build.sh --arch universal
ǩ���������ڱ���Կ�״����ã���Ŀ������֤���ƾ�ݡ�

ʹ��
1. ���������� .app ���������ѡ�񴰿ڲ���ͼ����
2. ��ϵͳѡ������ѡ��Ŀ�괰�ڲ�ȷ�ϡ�
3. ��ϵͳҪ����Ļ¼��Ȩ�ޣ�����ʾ��Ȩ��Ҳ�ɵ�������е���Ȩ��ϵͳ���ð�ť��
   ĳЩϵͳ�汾��Ҫ��Ȩ����ȫ�˳�����������Ӧ�á�
4. ��Ԥ�����鿴ʵ��ͼ���ٱ��� PNG ����ͼƬ��
5. ���ٴν�ͼ�����»�ȡͬһ��ѡ�񴰿ڣ����ڹرջ�ѡ��ʧЧ����Ҫ����ѡ��
6. �����Ԥ����ѡ���ͷ�ѡ���������Ԥ��������մ�ǰ�������Ƶ��������ͼƬ��

��ݼ�
Command+Shift+1  ѡ�񴰿ڲ���ͼ
Command+Shift+2  �ٴν�ͼ
Command+S        ���� PNG
Command+Shift+C  ����ͼƬ

�� Windows �������
��ʵ�ֲ����û�ȷ�ϵġ�ֱ�ӽ�ͼ��������
������ȡ���������̵Ĵ��ڱ�����Ҳ����ŵϵͳ��ݼ���������ͼ���������ͬ�����
�ɵ� NSWindow.sharingType = .none �ڽ��� macOS �п��ܲ�Ӱ�� ScreenCaptureKit��
��ͼ�Ƿ��������ʵ��Ԥ��Ϊ׼��DRM ��Ƶ��Ӧ���������ص������Կ��ܲ��ɼ���
��ͼ API ����ͼ�񲻱�ʾͼ��һ������Ŀ�����ݣ�����ǰ��鿴Ԥ����
�ɰ汾 macOS �����ñ����Ĵ���Ҳ�����޷�ѡȡ�����ͼΪ�հס�
Ӧ������ʱ��������ȡ���棻�����û�ѡ��������֡��ͼ��
ϵͳѡ��������Ȩ��ϵͳ����Ļ¼����Ȩ���������� macOS �汾�еȼۡ�
����֡��ͼ API ���ؾܾ����ʣ��밴ϵͳ��ʾ��Ȩ����Ӧ��ѡ����ȷ����Ϊ�Ѿ����ȫ��Ȩ�ޡ�

Դ��
Package.swift                         Swift Package Manager ��Ŀ
Sources/CaptureAccessMac/             SwiftUI ��Ӧ�á�ϵͳѡ�������ͼ�߼�
Sources/CaptureCore/                  �ߴ��� PNG ����
Sources/CaptureAccessDemo/            �����ı������Դ���
Resources/                           Ӧ�ü���ʾӦ�õ� Info.plist
Tests/CaptureCoreTests/               �ߴ�߽硢Retina �ߴ硢PNG ���������ز���
Tests/MANUAL-TESTS.txt                ϵͳȨ������ʵ��ͼ�ֶ����ղ���
build.sh                             ������ǩ���� ZIP ����ű�

����
  cd macos
  swift test
����ֻ���ͼ������ߴ���Ϊ�����Ὺ����Ļ¼�ơ�
���桢��Ȩ��Ŀ�괰�ں;�ʽ������Ϊ��Ҫ�� Tests/MANUAL-TESTS.txt �� Mac ��ʵ�⡣
��Ҫֱ���� swift run ������ʽ .app ���գ��� Bundle ʱ��Ȩ�����ݡ���ʾ·����������Ϊ���ܲ�ͬ��

��ǰ��֤״̬
���ο��������� Windows��û�� macOS SDK��
macOS ԭ�����롢��Ԫ���ԡ�Ȩ�����̺ͽ�ͼЧ������δִ�С�
��ִ�еľ�̬����¼�� TEST-REPORT.txt��

GitHub macOS ����
�ֿ��Ŀ¼�� .github/workflows/build-macos.yml ֧���ֶ�������
�� GitHub Actions ��ѡ�� Build macOS app��ѡ�� universal / arm64 / x86_64��
���� macos-15 �������� swift test �ͱ�Ŀ¼�� build.sh�����ϴ�Ӧ�� ZIP ��У��ֵ��
����ԭ������ʹ�������� Mac ��ִ�У���ǰ��δ����������

�ӿڲο����ٷ���
https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
https://www.electronjs.org/docs/latest/api/browser-window#winsetcontentprotectionenable-macos-windows
