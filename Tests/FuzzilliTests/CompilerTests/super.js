class Animal {
    constructor(name) {
      this.name = name;
    }
    set name(value) {
      this._name = value;
    }
    get name() {
      return this._name;
    }
    speak() {
      console.log("Animal speaks!"); // CallSuperMethod
    }
  }
  
  class Dog extends Animal {
    constructor(name) {
      super(name); // CallSuperConstructor
    }
    m() {
      super.name = "SuperDog"; // SetSuperProperty
      console.log(super.name); // GetSuperProperty
      super["name"] = "Bello"; // SetComputedSuperProperty
      console.log(super["name"]); // GetComputedSuperProperty
      super.speak(); // CallSuperMethod
    }
    updateName() {
      super.name += " Updated"; // UpdateSuperProperty
    }
  }
  
  const myDog = new Dog("Bello");
  myDog.m();
  myDog.updateName();
  console.log(myDog.name);