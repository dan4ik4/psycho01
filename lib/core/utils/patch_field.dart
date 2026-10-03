class PatchField<T> {
  final T? value;
  final bool isSet;

  const PatchField({this.value}) : isSet = true;
  const PatchField.unset() : value = null, isSet = false;
}