Capture Access
==============

��Ŀ�ṹ
windows/  Windows 10 / 11 �汾��ѡ�񴰿ں�ȡ�� SetWindowDisplayAffinity ��ͼ������
macos/    macOS 14+ ԭ���汾��ʹ��ϵͳ����ѡ������ֱ�ӽ�ͼ��Ԥ�������� PNG������ͼƬ��

Windows
����Ŀ��Ŀ¼�� PowerShell ��ִ�У�
  .\windows\build.ps1
���У�windows\dist\CaptureAccess.exe
���п����г���ԭ�� x86/x64 �������ʾ����͹����м��ļ������Ƶ� windows/��
��ϸ˵����windows/README.txt
���в��Խ����windows/TEST-REPORT.txt

macOS
��Ҫ Mac��macOS 14 ����°汾���Լ� Xcode 15+ / ��Ӧ Command Line Tools��
����Ŀ��Ŀ¼���ն���ִ�У�
  bash macos/build.sh
���У�macos/dist/CaptureAccess.app
ͬʱ���� Intel �� Apple Silicon ͨ��Ӧ�ã�
  bash macos/build.sh --arch universal
���е�Ԫ���ԣ�
  cd macos
  swift test
��ϸ˵����macos/README.txt
�ֶ����գ�macos/Tests/MANUAL-TESTS.txt

Զ�̴������ Mac ��ִ�У����� Windows �ϴ����
��Ŀ���ṩ .github/workflows/build-macos.yml��
����Ŀ�����Լ��� GitHub �ֿ���� Actions ��ѡ�� Build macOS app���ֶ�ִ�� Run workflow��
Ĭ������ͬʱ֧�� Apple Silicon �� Intel �� universal Ӧ�á�
���ԡ����롢ǩ���� ZIP ����������� GitHub �� macos-15 ������
�ɹ���ӹ����� Artifacts ���� ZIP��ѹ�������Ǵ�Ӧ�ð��ṹ�� CaptureAccess.app��
Ĭ�ϱ��� ad-hoc ǩ���������� Developer ID ǩ���� Apple ��֤��
��ǰ��׼���˹������̣���δ�ϴ��ֿ�������ƶ˹�����

��ƽ̨��ʵ�ֲ���
Windows ���޸���ѡ���ڵı�����־������ʹ��������ͼ���߲���
macOS �水�û�ȷ�ϵķ������ɱ����߻�ȡ��ѡ���ڵĽ�ͼ�������ṩ����̽�� sharingType �Ĺ��ܡ�
macOS ��ϵͳ����ѡ�����͵�֡��ͼ�� ScreenCaptureKit �ṩ��������ѭϵͳȨ����ʾ��
��ʽ���ڱ����ڽ��� macOS �п��ܲ���ֹ ScreenCaptureKit����˿��Գ��Զ����ര��ֱ�ӽ�ͼ��
DRM��Ӧ�������������ݻ��������������Կ��ܲ����հ�ͼ�񣬲���֤����Ŀ�궼�ɲ���

��֤��Χ
Windows�����к��ļ��ɲ���ͨ�����û���ǰ���ֶ�ȷ�ϲ��Կ��á�
macOS����ǰ��������Ϊ Windows��δִ�� macOS ԭ�����롢Swift ��Ԫ���Ի��ͼʵ�⡣
���� Mac ��ִ�й������ֶ����գ�Դ���еĲ�������������������ͨ����
