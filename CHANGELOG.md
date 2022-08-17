## 1.0.0 (2022-08-17)


### 💄 Styles

* add swift-format for code formatting ([001a1d2](https://github.com/SwiftyLab/AsyncObjects/commit/001a1d209ec8d3376481a82eb8368593863205c6))
* add vscode workspace settings ([92c5810](https://github.com/SwiftyLab/AsyncObjects/commit/92c58104533b1669ac03fbddb39b549e3fb04896))


### 🔥 Refactorings

* refactor continuation management to prevent race condition ([dfa3717](https://github.com/SwiftyLab/AsyncObjects/commit/dfa37179bda741a5fe9a5ae07bcb332b5c3a0394))
* use `CheckedContinuation` for debug mode or for `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag ([3899792](https://github.com/SwiftyLab/AsyncObjects/commit/3899792d50f41b1653aeef10ba0177b8b5730188))


### ✅ Tests

* add async countdown event tests ([8e07add](https://github.com/SwiftyLab/AsyncObjects/commit/8e07add1715eabe8a225acc232af2f0688f5fe94))
* add async event tests ([ad42d72](https://github.com/SwiftyLab/AsyncObjects/commit/ad42d7246e8dd1b044f81da1d2353838535b0e2e))
* add async semaphore tests ([fd075bd](https://github.com/SwiftyLab/AsyncObjects/commit/fd075bd737833d97bf06c426c1fbba4e53473a6a))
* add future tests ([43a209e](https://github.com/SwiftyLab/AsyncObjects/commit/43a209e8c4019d68bdba85ca2f1cfe8c2ced5f28))
* add task queue tests ([bbb8188](https://github.com/SwiftyLab/AsyncObjects/commit/bbb8188b57c9868b623438beb75b5dc5d9ef553c))
* add tests for cancellation source ([3e81653](https://github.com/SwiftyLab/AsyncObjects/commit/3e816532fcf0fe5dd2b866f90bea7bd5257a39de))
* add tests for multiple synchronization objects wait ([dc56f4e](https://github.com/SwiftyLab/AsyncObjects/commit/dc56f4e01f2d126c9758505e3e30356b04d38f61))
* add tests for structured concurrency-GCD bridge ([7b36c93](https://github.com/SwiftyLab/AsyncObjects/commit/7b36c93add3d72973ac1b3f88097d27691be3812))
* remove methods usage not supported on linux ([485452c](https://github.com/SwiftyLab/AsyncObjects/commit/485452c5d75de9da7a170a1e32caab06d02e5a7c))


### 🚀 Features

* add `barrier` and `block` flags for `TaskQueue` ([d3e566a](https://github.com/SwiftyLab/AsyncObjects/commit/d3e566a32fe4ad9fc897609dcae84ab799fa65b8))
* add async countdown event ([f138abc](https://github.com/SwiftyLab/AsyncObjects/commit/f138abcafbef3469aa63ed2c5bcf62267f07127b))
* add async event ([dc3090c](https://github.com/SwiftyLab/AsyncObjects/commit/dc3090ce79be709130910ee9962d32dc6ebc7a6b))
* add async semaphore ([fbd6b65](https://github.com/SwiftyLab/AsyncObjects/commit/fbd6b6537060cbc6dd261b4a0f0b97b64542209d))
* add cancellation source for controlling multiple tasks cooperative cancellation ([b92665d](https://github.com/SwiftyLab/AsyncObjects/commit/b92665d8a216ce5b450fe2336f7148e38752a35b))
* add CocoaPods support ([646db5b](https://github.com/SwiftyLab/AsyncObjects/commit/646db5bcfbb1d8d49b6707a20c321540f141c362))
* add operation type to bridge GCD/`libdispatch` with structured concurrency ([51b302e](https://github.com/SwiftyLab/AsyncObjects/commit/51b302e00537e4def872a7888439f47ae2bf5c9a))
* add option to provide number of objects to wait for ([20b5725](https://github.com/SwiftyLab/AsyncObjects/commit/20b5725c6e6f59d79f562d32adcc2dd76688d52d))
* add priority based task execution on `TaskQueue` ([df5e6e7](https://github.com/SwiftyLab/AsyncObjects/commit/df5e6e7ece9c4c775aaac8d5c69338948ce60d66))
* add task queue to run concurrent tasks and barrier tasks similar to DispatchQueue ([84e4d29](https://github.com/SwiftyLab/AsyncObjects/commit/84e4d29370fff9695911b0dee89aa33fa06cce20))
* add transfering data across tasks with `Future` ([d4d658f](https://github.com/SwiftyLab/AsyncObjects/commit/d4d658fa1bd1c9381ab1facd133bc39e3afeff8d))
* add wait for multiple synchronization objects ([68702b5](https://github.com/SwiftyLab/AsyncObjects/commit/68702b5522ec04e329fb839e72d034a50149e9ef))


### 📚 Documentation

* add contributing guidelines ([e4a78ee](https://github.com/SwiftyLab/AsyncObjects/commit/e4a78ee75205d27868edb5d3ad56e8735f84256c))
* add docC calatalog for library ([9e69dbb](https://github.com/SwiftyLab/AsyncObjects/commit/9e69dbb6d6d066ebfe04d920f96154e30a50af96))
* add github pages product specific documentation ([05e1e30](https://github.com/SwiftyLab/AsyncObjects/commit/05e1e30afe744bb69ce0998ddb9eb03859806226))
* add installation and usage guidelines ([0b4df47](https://github.com/SwiftyLab/AsyncObjects/commit/0b4df47b0e023d3553bcb06c7b9175ff3d6a033e))

