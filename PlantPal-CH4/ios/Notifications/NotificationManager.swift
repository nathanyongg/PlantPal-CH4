//
//  NotificationManager.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
internal import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    static let shared = NotificationManager()

    enum Category {
        static let plantHealth = "plant_health"
        static let sensorStatus = "sensor_status"
        static let dailyReminder = "daily_reminder"
    }

    private let center = UNUserNotificationCenter.current()
    private let dailyReminderIdentifier = "plantpal.daily-care-reminder"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var fcmToken: String?
    @Published private(set) var remoteRegistrationError: String?

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        Messaging.messaging().delegate = self
        registerCategories()

        Task {
            await refreshAuthorizationStatus()
            if authorizationStatus == .authorized || authorizationStatus == .provisional {
                await scheduleDailyReminderIfNeeded()
            }
        }
    }

    @discardableResult
    func requestAuthorization(registerForPush: Bool = false) async -> Bool {
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                remoteRegistrationError = error.localizedDescription
            }
        }

        await refreshAuthorizationStatus()

        let isAuthorized = authorizationStatus == .authorized || authorizationStatus == .provisional
        UserDefaults.standard.set(isAuthorized, forKey: "notificationsEnabled")

        if isAuthorized {
            await scheduleDailyReminderIfNeeded()
            if registerForPush {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        return isAuthorized
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func handleRemoteRegistration(deviceToken: Data) {
        self.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Messaging.messaging().apnsToken = deviceToken
        remoteRegistrationError = nil
    }

    func handleRemoteRegistration(error: Error) {
        remoteRegistrationError = error.localizedDescription
    }

    func schedulePlantHealthAlert(
        title: String,
        body: String,
        isCritical: Bool,
        plantID: String? = nil
    ) async {
        guard notificationsEnabled else { return }
        guard !isCritical || criticalAlertsEnabled else { return }
        guard await canDeliverNotifications() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isCritical ? .defaultCritical : .default
        content.categoryIdentifier = Category.plantHealth
        if let plantID {
            content.userInfo = ["plant_id": plantID]
        }

        await add(
            content: content,
            identifier: "plantpal.health.\(plantID ?? UUID().uuidString)"
        )
    }

    func scheduleSensorStatusAlert(body: String) async {
        guard notificationsEnabled else { return }
        guard await canDeliverNotifications() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Can't reach your plant sensor"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Category.sensorStatus

        await add(content: content, identifier: "plantpal.sensor.\(UUID().uuidString)")
    }

    func scheduleDailyReminderIfNeeded() async {
        guard notificationsEnabled, dailyReminderEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
            return
        }
        guard await canDeliverNotifications() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Plant check-in"
        content.body = "Take a quick look at your plants today."
        content.sound = .default
        content.categoryIdentifier = Category.dailyReminder

        var components = DateComponents()
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            remoteRegistrationError = error.localizedDescription
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }

    private func canDeliverNotifications() async -> Bool {
        await refreshAuthorizationStatus()
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private func add(content: UNMutableNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            remoteRegistrationError = error.localizedDescription
        }
    }

    private func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: "open_app",
            title: "Open PlantPal",
            options: [.foreground]
        )

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: Category.plantHealth,
                actions: [openAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.sensorStatus,
                actions: [openAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.dailyReminder,
                actions: [openAction],
                intentIdentifiers: []
            )
        ]

        center.setNotificationCategories(categories)
    }

    private var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    private var criticalAlertsEnabled: Bool {
        UserDefaults.standard.object(forKey: "criticalAlerts") as? Bool ?? true
    }

    private var dailyReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: "dailyReminder") as? Bool ?? true
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

extension NotificationManager: MessagingDelegate {

    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken else { return }

        Task { @MainActor in
            self.fcmToken = fcmToken
            do {
                try await FirestoreService.shared.uploadDeviceToken(fcmToken)
            } catch {
                self.remoteRegistrationError = error.localizedDescription
            }
        }
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        Task { @MainActor in
            NotificationManager.shared.configure()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRemoteRegistration(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRemoteRegistration(error: error)
        }
    }
}
