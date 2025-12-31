@echo off
:: 设置 Flutter 镜像环境变量
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

:: 进入项目目录（确保路径正确）
cd /d D:\flutter_projects\hello_flutter

:: 清理缓存
flutter clean

:: 获取依赖
flutter pub get

:: 运行 Flutter Web
flutter run -d chrome

pause
