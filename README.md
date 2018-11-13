# CastVideos-ios (reference iOS sender app)

This Google Cast demo app shows how to cast videos from an iOS device in a way that is fully compliant with the Cast Design Checklist.

**This is a reference sender app to be used as the starting point for your iOS sender app. The project contains targets for both Objective-C and Swift.**

Here is the list of other reference apps:
* [Android Sender: CastVideos-android](https://github.com/googlecast/CastVideos-android)
* [Chrome Sender: CastVideos-chrome](https://github.com/googlecast/CastVideos-chrome)
* [CAF Receiver: CastReceiver](https://github.com/googlecast/CastReceiver)

## Dependencies
* iOS Sender API library : can be downloaded here at: [https://developers.google.com/cast/docs/ios_sender_setup](https://developers.google.com/cast/docs/ios_sender_setup "iOS Sender API library")

## Setup Instructions
* Get a Chromecast device and get it set up for development: https://developers.google.com/cast/docs/developers#Get_started
* [Optional] Register an application on the Developers Console [http://cast.google.com/publish](http://cast.google.com/publish "Google Cast Developer Console"). The easiest would be to use the Styled Media Receiver option there. You will get an App ID when you finish registering your application. This project uses a published Application ID that
can be used to run the app without using your own ID but if you need to do any console debugging, you would need
to have your own ID.
* Setup the project dependencies in Xcode using Cocoapods. If necessary, install Cocoapods: See this [guide](http://guides.cocoapods.org/using/getting-started.html). In the CastVideos-ios directory, run `pod repo update` and then `pod install`. Open CastVideos-ios.xcworkspace
* This sample includes a published app id in the user defaults so the project can be built and run without a need
   to register an app id. If you want to use your own receiver (which is required if you need to debug the receiver),
    update the user defaults or AppDelegate.m with your own app id.
* Xcode setup steps: https://developers.google.com/cast/docs/ios_sender_setup#xcode_setup

## Documentation
* [Google Cast iOS Sender Overview](https://developers.google.com/cast/docs/ios_sender/)
* [Developer Guides](https://developers.google.com/cast/docs/developers)

## References
* [iOS Sender Reference](https://developers.google.com/cast/docs/reference/ios/)
* [Design Checklist](http://developers.google.com/cast/docs/design_checklist)

## How to report bugs
* [Google Cast SDK Support](https://developers.google.com/cast/docs/support)
* For sample apps issues, please open a bug here on GitHub

## How to make contributions?
Please read and follow the steps in the [CONTRIBUTING.md](CONTRIBUTING.md)

## License
See [LICENSE](LICENSE)

## Terms
Your use of this sample is subject to, and by using or downloading the sample files you agree to comply with, the [Google APIs Terms of Service](https://developers.google.com/terms/) and the [Google Cast SDK Additional Developer Terms of Service](https://developers.google.com/cast/docs/terms/).

## Google+
[Google Cast Developers Community on Google+](http://goo.gl/TPLDxj)
