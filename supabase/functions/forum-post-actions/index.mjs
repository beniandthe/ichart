import {
  createForumPostActionDependencies,
  handleForumPostActionRequest,
} from "../_shared/forum_post_actions.mjs";

const dependencies = createForumPostActionDependencies();

Deno.serve((request) => handleForumPostActionRequest(request, dependencies));
