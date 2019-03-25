# CastVideos-ios (reference iOS sender app)

This Google Cast demo app shows how to cast videos from an iOS device in a way that is fully compliant with the Cast Design Checklist.

**This is a reference sender app to be used as the starting point for your iOS sender app. The project contains targets for both Objective-C and Swift.**

[List of reference apps and tutorials](https://developers.google.com/cast/docs/downloads)

## Setup Instructions
1. Get a Google Cast device and get it set up for development: https://developers.google.com/cast/docs/developers#setup_for_development.
1. [Optional] Register an application on the Developers Console [http://cast.google.com/publish](http://cast.google.com/publish "Google Cast Developer Console").
  The easiest would be to use the Styled Media Receiver option. You will get an App ID when you finish registering your application. This project uses a
  published Application ID that can be used to run the app without using your own ID but if you need to do any console debugging, you would need to have your own ID.
1. Setup the project dependencies in Xcode using Cocoapods, installing the tool if necessary: See this [guide](http://guides.cocoapods.org/using/getting-started.html).
1. In the root folder, run `pod repo update` and then `pod install`.
1. Open the .xcworkspace file rather the the xcproject to ensure you have the pod dependencies.
1. In AppDelegate.swift/AppDelegate.m the sample includes a published receiver app ID so the project can be built and run without a need
  to register an ID. If you want to use your own receiver (which is required if you need to debug the receiver), update the value with your own ID.
1. [Xcode setup steps](https://developers.google.com/cast/docs/ios_sender_setup#xcode_setup)

## Documentation
* [Google Cast iOS Sender Overview](https://developers.google.com/cast/docs/ios_sender/)
* [Developer Guides](https://developers.google.com/cast/docs/developers)

## References
* [iOS Sender Reference](https://developers.google.com/cast/docs/reference/ios/)
* [Design Checklist](http://developers.google.com/cast/docs/design_checklist)

## How to report bugs
* [Google Cast SDK Support](https://developers.google.com/cast/support)
* For sample app issues, open an issue on this GitHub repo.

## Contributions
Please read and follow the steps in the [CONTRIBUTING.md](CONTRIBUTING.md).

## License
See [LICENSE](LICENSE).

## Terms
Your use of this sample is subject to, and by using or downloading the sample files you agree to comply with, the [Google APIs Terms of Service](https://developers.google.com/terms/) and the [Google Cast SDK Additional Developer Terms of Service](https://developers.google.com/cast/docs/terms/).
