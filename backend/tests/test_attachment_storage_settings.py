def test_test_settings_use_ignored_local_attachment_root(settings):
    assert settings.EMPLOYEE_ATTACHMENT_MAX_BYTES == 10 * 1024 * 1024
    assert settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT.name == "employee-attachments"


def test_attachment_uploads_default_to_private_filesystem_permissions(settings):
    assert settings.FILE_UPLOAD_PERMISSIONS == 0o600
    assert settings.FILE_UPLOAD_DIRECTORY_PERMISSIONS == 0o700
