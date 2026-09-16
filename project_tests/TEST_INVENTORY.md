# Complete test inventory

Final run: **98 tests, 96 PASS, 2 FAIL**. Old/new means present before this task or added during it. Each row describes one unittest method; subcases are not counted as independent tests. DD mapping indicates related coverage, not complete group acceptance.

| Case | Origin | DD / acceptance link | Check | Result |
| --- | --- | --- | --- | --- |
| [`AccessIntegrityTests.test_deleted_account_token_is_rejected`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | deleted account token is rejected | **PASS** |
| [`AccessIntegrityTests.test_event_writes_require_current_director_role`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | event writes require current director role | **PASS** |
| [`AccessIntegrityTests.test_idle_websocket_revalidates_and_unsubscribes`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | idle websocket revalidates and unsubscribes | **PASS** |
| [`AccessIntegrityTests.test_invalid_csv_preserves_previous_results`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | invalid csv preserves previous results | **PASS** |
| [`AccessIntegrityTests.test_partial_csv_replaces_results_and_reports_errors`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | partial csv replaces results and reports errors | **PASS** |
| [`AccessIntegrityTests.test_websocket_uses_current_account`](backend/test_access_integrity.py) | Existing | T1, T2, T5, T8, T12 | websocket uses current account | **PASS** |
| [`DocumentAcceptanceTests.test_A1_duplicate_registration`](backend/test_document_acceptance.py) | New | A1 | A1 duplicate registration | **PASS** |
| [`DocumentAcceptanceTests.test_A2_late_registration_enters_waitlist`](backend/test_document_acceptance.py) | New | A2 | A2 late registration enters waitlist | **PASS** |
| [`DocumentAcceptanceTests.test_A3_account_cannot_change_roles`](backend/test_document_acceptance.py) | New | A3 | A3 account cannot change roles | **PASS** |
| [`DocumentAcceptanceTests.test_A3_foreign_team_edit_denied`](backend/test_document_acceptance.py) | New | A3 | A3 foreign team edit denied | **PASS** |
| [`DocumentAcceptanceTests.test_A4_source_and_event_isolation`](backend/test_document_acceptance.py) | New | A4 | A4 source and event isolation | **PASS** |
| [`DocumentAcceptanceTests.test_A8_waiver_preview_store_pdf_remove`](backend/test_document_acceptance.py) | New | A8 | A8 waiver preview store pdf remove | **PASS** |
| [`DocumentAcceptanceTests.test_T10_durable_records_after_engine_reopen`](backend/test_document_acceptance.py) | New | T10 | T10 durable records after engine reopen | **PASS** |
| [`DocumentAcceptanceTests.test_T12_deleted_account_cannot_download_waiver`](backend/test_document_acceptance.py) | New | T12 | T12 deleted account cannot download waiver | **PASS** |
| [`DocumentAcceptanceTests.test_T12_demoted_token_cannot_download_waiver`](backend/test_document_acceptance.py) | New | T12 | T12 demoted token cannot download waiver | **PASS** |
| [`DocumentAcceptanceTests.test_T12_private_database_is_not_public_static_asset`](backend/test_document_acceptance.py) | New | T12 | T12 private database is not public static asset | **FAIL** (F1) |
| [`DocumentAcceptanceTests.test_T1_duplicate_identity_rejected`](backend/test_document_acceptance.py) | New | T1 | T1 duplicate identity rejected | **PASS** |
| [`DocumentAcceptanceTests.test_T1_expired_token_rejected`](backend/test_document_acceptance.py) | New | T1 | T1 expired token rejected | **PASS** |
| [`DocumentAcceptanceTests.test_T1_profile_cannot_promote_self`](backend/test_document_acceptance.py) | New | T1 | T1 profile cannot promote self | **PASS** |
| [`DocumentAcceptanceTests.test_T1_register_login_refresh_logout`](backend/test_document_acceptance.py) | New | T1 | T1 register login refresh logout | **PASS** |
| [`DocumentAcceptanceTests.test_T2_confirmed_self_cancellation_blocked`](backend/test_document_acceptance.py) | New | T2 | T2 confirmed self cancellation blocked | **PASS** |
| [`DocumentAcceptanceTests.test_T2_full_individual_event_enters_waitlist`](backend/test_document_acceptance.py) | New | T2 | T2 full individual event enters waitlist | **PASS** |
| [`DocumentAcceptanceTests.test_T4_empty_signature_is_rejected`](backend/test_document_acceptance.py) | New | T4 | T4 empty signature is rejected | **FAIL** (F2) |
| [`DocumentAcceptanceTests.test_T4_unregistered_cannot_sign_or_read_other_waiver`](backend/test_document_acceptance.py) | New | T4 | T4 unregistered cannot sign or read other waiver | **PASS** |
| [`DocumentAcceptanceTests.test_T4_upload_exact_limit_and_one_byte_over`](backend/test_document_acceptance.py) | New | T4 | T4 upload exact limit and one byte over | **PASS** |
| [`DocumentAcceptanceTests.test_T5_shared_source_and_switch_preserve_other_client`](backend/test_document_acceptance.py) | New | T5 | T5 shared source and switch preserve other client | **PASS** |
| [`DocumentAcceptanceTests.test_T5_simulator_normalization_and_factory`](backend/test_document_acceptance.py) | New | T5 | T5 simulator normalization and factory | **PASS** |
| [`DocumentAcceptanceTests.test_T6_assignment_conflict_preserves_existing_entries`](backend/test_document_acceptance.py) | New | T6 | T6 assignment conflict preserves existing entries | **PASS** |
| [`DocumentAcceptanceTests.test_T7_warning_threshold_creates_configured_penalty`](backend/test_document_acceptance.py) | New | T7 | T7 warning threshold creates configured penalty | **PASS** |
| [`DocumentAcceptanceTests.test_T8_import_authorization_through_http`](backend/test_document_acceptance.py) | New | T8 | T8 import authorization through http | **PASS** |
| [`DocumentAcceptanceTests.test_T8_valid_import_preserves_other_events`](backend/test_document_acceptance.py) | New | T8 | T8 valid import preserves other events | **PASS** |
| [`EventExpirationNotificationTests.test_notifies_clients_after_scan`](backend/test_event_lifecycle.py) | Existing | T9 | notifies clients after scan | **PASS** |
| [`EventLifecycleTests.test_aware_now_is_converted_to_utc`](backend/test_event_lifecycle.py) | Existing | T9 | aware now is converted to utc | **PASS** |
| [`EventLifecycleTests.test_closes_only_events_at_least_two_days_old`](backend/test_event_lifecycle.py) | Existing | T9 | closes only events at least two days old | **PASS** |
| [`EventLifecycleTests.test_exact_48_hour_boundary_including_daylight_saving_changes`](backend/test_event_lifecycle.py) | Existing | T9 | exact 48 hour boundary including daylight saving changes | **PASS** |
| [`EventRegistrationIntegrityTests.test_complete_team_accepting_extra_pilots_is_not_waitlisted`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | complete team accepting extra pilots is not waitlisted | **PASS** |
| [`EventRegistrationIntegrityTests.test_deadline_follows_date_and_respects_explicit_override`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | deadline follows date and respects explicit override | **PASS** |
| [`EventRegistrationIntegrityTests.test_duplicate_edit_preserves_team`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | duplicate edit preserves team | **PASS** |
| [`EventRegistrationIntegrityTests.test_duplicates_rejected_before_insert`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | duplicates rejected before insert | **PASS** |
| [`EventRegistrationIntegrityTests.test_edit_below_minimum_preserves_team`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | edit below minimum preserves team | **PASS** |
| [`EventRegistrationIntegrityTests.test_edit_incomplete_team_rejected_even_when_accepting_extra_pilots`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | edit incomplete team rejected even when accepting extra pilots | **PASS** |
| [`EventRegistrationIntegrityTests.test_explicit_max_is_enforced`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | explicit max is enforced | **PASS** |
| [`EventRegistrationIntegrityTests.test_extra_pilots_does_not_bypass_maximum`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | extra pilots does not bypass maximum | **PASS** |
| [`EventRegistrationIntegrityTests.test_generic_status_patch_rejected_without_changes`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | generic status patch rejected without changes | **PASS** |
| [`EventRegistrationIntegrityTests.test_incomplete_team_rejected_even_when_accepting_extra_pilots`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | incomplete team rejected even when accepting extra pilots | **PASS** |
| [`EventRegistrationIntegrityTests.test_member_replacement`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | member replacement | **PASS** |
| [`EventRegistrationIntegrityTests.test_minimum_and_maximum_inclusive`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | minimum and maximum inclusive | **PASS** |
| [`EventRegistrationIntegrityTests.test_minimum_one_allows_solo_registration`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | minimum one allows solo registration | **PASS** |
| [`EventRegistrationIntegrityTests.test_minimum_rejects_missing_and_blank_members_without_insert`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | minimum rejects missing and blank members without insert | **PASS** |
| [`EventRegistrationIntegrityTests.test_no_team_name_registers_individual_in_waitlist_despite_minimum`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | no team name registers individual in waitlist despite minimum | **PASS** |
| [`EventRegistrationIntegrityTests.test_optional_max_and_rename_preserve_member_attributes`](backend/test_event_registration_integrity.py) | Existing | T2, T3 | optional max and rename preserve member attributes | **PASS** |
| [`EventReminderTests.test_boundary_refresh_and_deletion`](backend/test_event_reminders.py) | Existing | T9 | boundary refresh and deletion | **PASS** |
| [`EventReminderTests.test_excluded_waitlist_started_and_past_events`](backend/test_event_reminders.py) | Existing | T9 | excluded waitlist started and past events | **PASS** |
| [`EventReminderTests.test_registration_inside_window_before_confirmation`](backend/test_event_reminders.py) | Existing | T9 | registration inside window before confirmation | **PASS** |
| [`EventReminderTests.test_rollback_does_not_consume_reminder`](backend/test_event_reminders.py) | Existing | T9 | rollback does not consume reminder | **PASS** |
| [`KartodromoUpdateTests.test_disconnect_precedes_save_and_only_affects_target`](backend/test_kartodromo_update.py) | Existing | T5, T12 | disconnect precedes save and only affects target | **PASS** |
| [`KartodromoUpdateTests.test_duplicate_url_does_not_disconnect`](backend/test_kartodromo_update.py) | Existing | T5, T12 | duplicate url does not disconnect | **PASS** |
| [`KartodromoUpdateTests.test_live_event_blocks_without_disconnect_or_changes`](backend/test_kartodromo_update.py) | Existing | T5, T12 | live event blocks without disconnect or changes | **PASS** |
| [`KartodromoUpdateTests.test_save_without_connected_clients`](backend/test_kartodromo_update.py) | Existing | T5, T12 | save without connected clients | **PASS** |
| [`KartodromoUpdateTests.test_timeout_aborts_save_and_unblocks_url`](backend/test_kartodromo_update.py) | Existing | T5, T12 | timeout aborts save and unblocks url | **PASS** |
| [`LapStatsTests.test_unique_route_and_per_kart_threshold`](backend/test_lap_stats.py) | Existing | T8 | unique route and per kart threshold | **PASS** |
| [`MessageScopeTests.test_stop_flags_require_explicit_restart`](backend/test_live_message_scope.py) | Existing | T6 | stop flags require explicit restart | **PASS** |
| [`MessageScopeTests.test_targeted_control_commands_are_rejected_without_side_effects`](backend/test_live_message_scope.py) | Existing | T6 | targeted control commands are rejected without side effects | **PASS** |
| [`MessageScopeTests.test_targeted_information_remains_supported`](backend/test_live_message_scope.py) | Existing | T6 | targeted information remains supported | **PASS** |
| [`NotificationIntegrityTests.test_event_and_notifications_rollback_together_on_failure`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | event and notifications rollback together on failure | **PASS** |
| [`NotificationIntegrityTests.test_expiry_accepts_database_dates_and_preserves_recent_notifications`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | expiry accepts database dates and preserves recent notifications | **PASS** |
| [`NotificationIntegrityTests.test_inbox_ownership_read_and_delete`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | inbox ownership read and delete | **PASS** |
| [`NotificationIntegrityTests.test_new_event_persists_one_notification_per_eligible_account`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | new event persists one notification per eligible account | **PASS** |
| [`NotificationIntegrityTests.test_sender_without_linked_account_does_not_create_notification`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | sender without linked account does not create notification | **PASS** |
| [`NotificationIntegrityTests.test_start_event_notifies_confirmed_and_removes_unconfirmed`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | start event notifies confirmed and removes unconfirmed | **PASS** |
| [`NotificationIntegrityTests.test_team_actions_notify_all_linked_members`](backend/test_notifications_integrity.py) | Existing | T2, T3, T9, T12 | team actions notify all linked members | **PASS** |
| [`PDFBrowserTests.test_expiry`](backend/test_pdf_browser.py) | Existing | T4, T12 | expiry | **PASS** |
| [`PDFBrowserTests.test_publish_and_open`](backend/test_pdf_browser.py) | Existing | T4, T12 | publish and open | **PASS** |
| [`PDFBrowserTests.test_unknown_link`](backend/test_pdf_browser.py) | Existing | T4, T12 | unknown link | **PASS** |
| [`PDFBrowserTests.test_validation`](backend/test_pdf_browser.py) | Existing | T4, T12 | validation | **PASS** |
| [`PenaltyConfigurationTests.test_duplicate_codes_keep_current_configuration`](backend/test_penalty_configuration.py) | Existing | T7 | duplicate codes keep current configuration | **PASS** |
| [`PenaltyConfigurationTests.test_legacy_migration_preserves_history_and_configuration`](backend/test_penalty_configuration.py) | Existing | T7 | legacy migration preserves history and configuration | **PASS** |
| [`PenaltyConfigurationTests.test_restart_preserves_custom_seconds_and_thresholds`](backend/test_penalty_configuration.py) | Existing | T7 | restart preserves custom seconds and thresholds | **PASS** |
| [`PenaltySecondsValidationTests.test_accepts_zero_positive_and_optional_seconds`](backend/test_penalty_configuration.py) | Existing | T7 | accepts zero positive and optional seconds | **PASS** |
| [`PenaltySecondsValidationTests.test_rejects_negative_and_non_integer_seconds`](backend/test_penalty_configuration.py) | Existing | T7 | rejects negative and non integer seconds | **PASS** |
| [`PenaltyThresholdValidationTests.test_accepts_positive_thresholds_and_unchanged_value`](backend/test_penalty_configuration.py) | Existing | T7 | accepts positive thresholds and unchanged value | **PASS** |
| [`PenaltyThresholdValidationTests.test_rejects_invalid_thresholds`](backend/test_penalty_configuration.py) | Existing | T7 | rejects invalid thresholds | **PASS** |
| [`StintPenaltyTests.test_pause_and_disabled_limit`](backend/test_stint_monitor.py) | Existing | T6, T7 | pause and disabled limit | **PASS** |
| [`StintPenaltyTests.test_pit_entry_checks_and_next_stint_rearms`](backend/test_stint_monitor.py) | Existing | T6, T7 | pit entry checks and next stint rearms | **PASS** |
| [`StintPenaltyTests.test_scan_persists_across_sessions`](backend/test_stint_monitor.py) | Existing | T6, T7 | scan persists across sessions | **PASS** |
| [`StintPenaltyTests.test_stale_worker_cannot_duplicate_penalty`](backend/test_stint_monitor.py) | Existing | T6, T7 | stale worker cannot duplicate penalty | **PASS** |
| [`StintPenaltyTests.test_threshold_once_and_admin_deletion`](backend/test_stint_monitor.py) | Existing | T6, T7 | threshold once and admin deletion | **PASS** |
| [`TokenRenewalTests.test_deleted_account_cannot_refresh`](backend/test_token_renewal.py) | New | T1, T12 | deleted account cannot refresh token | **PASS** |
| [`TokenRenewalTests.test_legacy_database_gets_token_version_without_losing_accounts`](backend/test_token_renewal.py) | New | T1 | legacy database migration adds token_version without data loss | **PASS** |
| [`TokenRenewalTests.test_role_change_requires_refresh_and_old_token_never_revives`](backend/test_token_renewal.py) | New | T1, T12 | role change invalidates old token; refresh returns new-role token | **PASS** |
| [`TokenRenewalTests.test_unchanged_role_does_not_revoke_access`](backend/test_token_renewal.py) | New | T1 | unchanged role does not revoke existing token | **PASS** |
| [`BroadcastCleanupTests.test_event_only_client_failure_needs_no_scraper`](backend/test_ws_manager.py) | Existing | T5, T10 | event only client failure needs no scraper | **PASS** |
| [`BroadcastCleanupTests.test_failed_broadcast_releases_last_subscriber_once`](backend/test_ws_manager.py) | Existing | T5, T10 | failed broadcast releases last subscriber once | **PASS** |
| [`BroadcastCleanupTests.test_failure_preserves_other_subscribers_and_delivery`](backend/test_ws_manager.py) | Existing | T5, T10 | failure preserves other subscribers and delivery | **PASS** |
| [`WebSocketInputTests.test_cancellation_releases_subscriptions`](backend/test_ws_router.py) | Existing | T5, T10 | cancellation releases subscriptions | **PASS** |
| [`WebSocketInputTests.test_error_response_send_failure_releases_subscriptions`](backend/test_ws_router.py) | Existing | T5, T10 | error response send failure releases subscriptions | **PASS** |
| [`WebSocketInputTests.test_malformed_messages_allow_next_valid_command`](backend/test_ws_router.py) | Existing | T5, T10 | malformed messages allow next valid command | **PASS** |
| [`WebSocketInputTests.test_unexpected_receive_error_releases_subscriptions`](backend/test_ws_router.py) | Existing | T5, T10 | unexpected receive error releases subscriptions | **PASS** |
