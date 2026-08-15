enum MessageRole { user, assistant, system }

class ConversationMessage {
  final MessageRole role;
  final String text;
  final DateTime timestamp;

  ConversationMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '${role.name.toUpperCase()}: $text';
}
