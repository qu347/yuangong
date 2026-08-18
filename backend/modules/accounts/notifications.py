from django.core.mail import EmailMessage


class AccountNotificationService:
    def send_invitation(self, *, email, token, expires_at):
        EmailMessage(
            subject="企业员工管理系统账号邀请",
            body=(
                "你收到一个企业员工管理系统账号邀请。\n"
                f"一次性代码：{token}\n"
                f"有效期至：{expires_at.isoformat()}\n"
                "请仅在受信任的客户端中使用；如果不是本人操作请忽略。"
            ),
            to=[email],
        ).send(fail_silently=False)

    def send_password_reset(self, *, email, token, expires_at):
        EmailMessage(
            subject="企业员工管理系统密码重置",
            body=(
                "你请求重置企业员工管理系统密码。\n"
                f"一次性代码：{token}\n"
                f"有效期至：{expires_at.isoformat()}\n"
                "如果不是本人操作请忽略。"
            ),
            to=[email],
        ).send(fail_silently=False)
