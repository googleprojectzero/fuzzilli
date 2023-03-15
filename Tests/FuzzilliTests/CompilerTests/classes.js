if (typeof output === 'undefined') output = console.log;

class C0 {
}
let o = new C0;
output(o instanceof C0);

class C1 {
  x = 1;
  y = 2;
}
o = new C1;
output(o instanceof C0);
output(o instanceof C1);
output(o.x, o.y);

class C2 extends C1 {
}
o = new C2;
output(o instanceof C0);
output(o instanceof C1);
output(o instanceof C2);
output(o.x, o.y);

class C3 {
  a;
  b = 1337;
  1337 = "c";
  ["c"] = 1338;
  static 1338 = "d";
  static d = 1339;
  static [1339] = "e";
  static e;
}
o = new C3;
output(o.a);
output(o.b);
output(o.c);
output(o.d);
output(o.e);
output(o[1337]);
output(o[1338]);
output(o[1339]);
output(C3.a);
output(C3.b);
output(C3.c);
output(C3.d);
output(C3.e);
output(C3[1337]);
output(C3[1338]);
output(C3[1339]);

class C4 {
  a;
  constructor(a) {
    this.a = a;
  }
  getA() {
    return this.a;
  }

  get b() {
    return this.a;
  }
  set b(v) {
    this.a = v;
  }
}
o = new C4(42);
output(o.a);
output(o.getA());
output(o.b);
o.b = 43;
output(o.b);
output(o.a);

class C5 {
  static a = 42;
  static {
    output(this.a);
    this.b = 43;
  }
  static {
    output(this.a);
    output(this.b);
  }
}
output(C5.a);
output(C5.b);
