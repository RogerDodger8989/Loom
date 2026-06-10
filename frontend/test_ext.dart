class A {
  void _foo() {
    print('foo');
  }
}

extension AExt on A {
  void bar() {
    _foo();
  }
}

void main() {
  A().bar();
}
