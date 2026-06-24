import { application } from "./application"

const controllers = import.meta.glob("./**/*_controller.js", { eager: true })

Object.entries(controllers).forEach(([path, module]) => {
  if (!module.default) return

  const identifier = path
    .replace("./", "")
    .replace(/_controller\.js$/, "")
    .replace(/\//g, "--")
    .replace(/_/g, "-")

  application.register(identifier, module.default)
})
