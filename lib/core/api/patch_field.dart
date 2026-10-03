/// Вспомогательный класс для разграничения "поле не передано" и "поле сброшено в null"[cite: 8]
class PatchField<T> {
  const PatchField.absent()
      : isSet = false,
        value = null;

  const PatchField.value(this.value) : isSet = true;

  final bool isSet;
  final T? value;
}