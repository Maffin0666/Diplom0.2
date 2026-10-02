enum VoiceCommand { play, pause, next, previous, repeatFormula, unknown }

VoiceCommand parseVoiceCommand(String words) {
  final text = words.toLowerCase().replaceAll('ё', 'е').trim();
  if (text.contains('повтори формул') || text.contains('повторить формул')) {
    return VoiceCommand.repeatFormula;
  }
  if (text.contains('следующ')) {
    return VoiceCommand.next;
  }
  if (text.contains('предыдущ') || text.contains('назад')) {
    return VoiceCommand.previous;
  }
  if (text.contains('пауз') || text.contains('останови')) {
    return VoiceCommand.pause;
  }
  if (text.contains('воспроизвед') ||
      text.contains('воспроизвести') ||
      text.contains('продолжи') ||
      text.contains('слушать')) {
    return VoiceCommand.play;
  }
  return VoiceCommand.unknown;
}
